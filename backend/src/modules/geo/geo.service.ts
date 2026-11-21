import { Inject, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { fail } from '../../common/errors';

export const GEO_HTTP = 'GEO_HTTP';

export interface GeoPlace {
  /** Main line: house number + street, or a place name. */
  title: string;
  /** Ward, city and province. */
  subtitle: string;
  /** Full single-line address to store. */
  address: string;
  latitude: number;
  longitude: number;
}

// Mainland Vietnam plus near-shore islands (west, south, east, north).
const VN_BBOX = '102.1,8.2,109.6,23.4';
const TIMEOUT_MS = 5000;
const CACHE_LIMIT = 500;
const CACHE_TTL_MS = 24 * 3600 * 1000;
// Nominatim's public usage policy allows at most one request per second.
const REVERSE_SPACING_MS = 1100;

type Json = Record<string, unknown>;
const text = (v: unknown) => (typeof v === 'string' ? v.trim() : '');

/** Joins address parts in Vietnamese order, dropping blanks and repeats. */
function join(parts: string[]) {
  const seen = new Set<string>();
  return parts.filter((p) => {
    const key = p.toLowerCase();
    if (!p || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

/**
 * Address search for the delivery form. Results come from OpenStreetMap
 * services by default (Photon for type-ahead, Nominatim for a dropped pin),
 * restricted to Vietnam, cached, and paced to respect the public services.
 */
@Injectable()
export class GeoService {
  private readonly cache = new Map<string, { at: number; value: GeoPlace[] }>();
  private reverseQueue: Promise<unknown> = Promise.resolve();
  private lastReverseAt = 0;

  constructor(
    private readonly config: ConfigService,
    @Inject(GEO_HTTP) private readonly http: typeof fetch,
  ) {}

  private assertEnabled() {
    if (this.config.get('GEO_ENABLED') === 'false')
      fail(503, 'GEO_UNAVAILABLE', 'Address lookup is turned off');
  }

  private cached(key: string) {
    const hit = this.cache.get(key);
    if (!hit) return undefined;
    if (Date.now() - hit.at > CACHE_TTL_MS) {
      this.cache.delete(key);
      return undefined;
    }
    // Refresh recency for the simple LRU below.
    this.cache.delete(key);
    this.cache.set(key, hit);
    return hit.value;
  }

  private remember(key: string, value: GeoPlace[]) {
    this.cache.set(key, { at: Date.now(), value });
    while (this.cache.size > CACHE_LIMIT)
      this.cache.delete(this.cache.keys().next().value!);
  }

  private async get(url: URL): Promise<unknown> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
    try {
      const res = await this.http(url, {
        headers: {
          'User-Agent':
            this.config.get<string>('GEO_USER_AGENT') ?? 'WearlyShop/1.0',
          Accept: 'application/json',
          'Accept-Language': 'vi',
        },
        signal: controller.signal,
      });
      if (!res.ok) throw new Error(`status ${res.status}`);
      return await res.json();
    } catch {
      fail(503, 'GEO_UNAVAILABLE', 'Address lookup is temporarily unavailable');
    } finally {
      clearTimeout(timer);
    }
  }

  async suggest(query: string, near?: { lat: number; lng: number }) {
    this.assertEnabled();
    const q = query.trim().replace(/\s+/g, ' ');
    if (q.length < 3) return [];
    const key = `s:${q.toLowerCase()}:${near ? `${near.lat.toFixed(2)},${near.lng.toFixed(2)}` : ''}`;
    const hit = this.cached(key);
    if (hit) return hit;
    const url = new URL(this.config.getOrThrow<string>('GEO_SUGGEST_URL'));
    url.searchParams.set('q', q);
    url.searchParams.set('limit', '8');
    url.searchParams.set('bbox', VN_BBOX);
    if (near) {
      url.searchParams.set('lat', String(near.lat));
      url.searchParams.set('lon', String(near.lng));
    }
    const body = (await this.get(url)) as Json;
    const features = Array.isArray(body?.features) ? body.features : [];
    const places: GeoPlace[] = [];
    const seen = new Set<string>();
    for (const f of features as Json[]) {
      const place = photonPlace(f);
      if (!place || seen.has(place.address.toLowerCase())) continue;
      seen.add(place.address.toLowerCase());
      places.push(place);
      if (places.length === 6) break;
    }
    this.remember(key, places);
    return places;
  }

  async reverse(lat: number, lng: number) {
    this.assertEnabled();
    // ~1 m grid: nearby drags of the pin reuse one lookup.
    const key = `r:${lat.toFixed(5)},${lng.toFixed(5)}`;
    const hit = this.cached(key);
    if (hit) return hit[0] ?? null;
    const run = this.reverseQueue.then(async () => {
      const wait = this.lastReverseAt + REVERSE_SPACING_MS - Date.now();
      if (wait > 0) await new Promise((r) => setTimeout(r, wait));
      this.lastReverseAt = Date.now();
      const url = new URL(this.config.getOrThrow<string>('GEO_REVERSE_URL'));
      url.searchParams.set('format', 'jsonv2');
      url.searchParams.set('lat', String(lat));
      url.searchParams.set('lon', String(lng));
      url.searchParams.set('zoom', '18');
      url.searchParams.set('addressdetails', '1');
      url.searchParams.set('accept-language', 'vi');
      return this.get(url);
    });
    // Keep the queue alive after a failure.
    this.reverseQueue = run.catch(() => undefined);
    const place = nominatimPlace((await run) as Json, lat, lng);
    this.remember(key, place ? [place] : []);
    return place;
  }
}

export function photonPlace(feature: Json): GeoPlace | null {
  const p = (feature?.properties ?? {}) as Json;
  const geometry = (feature?.geometry ?? {}) as Json;
  const coords = Array.isArray(geometry.coordinates)
    ? (geometry.coordinates as unknown[])
    : [];
  const [lng, lat] = coords;
  if (text(p.countrycode).toUpperCase() !== 'VN') return null;
  if (typeof lat !== 'number' || typeof lng !== 'number') return null;
  const name = text(p.name),
    street = text(p.street),
    house = text(p.housenumber);
  const road = house && street ? `${house} ${street}` : street;
  // A street feature carries its own name in `name`.
  const isStreet = text(p.type) === 'street' || text(p.osm_key) === 'highway';
  const title = isStreet
    ? name || road
    : house && street
      ? name && name !== road
        ? `${name}, ${road}`
        : road
      : name || road;
  if (!title) return null;
  const area = join([
    text(p.locality),
    text(p.district),
    text(p.city),
    text(p.county),
    text(p.state),
  ]).filter((a) => a.toLowerCase() !== title.toLowerCase());
  // A named place without a house number still needs its street.
  const lead = road && !title.includes(road) ? [title, road] : [title];
  return {
    title,
    subtitle: area.join(', '),
    address: join([...lead, ...area]).join(', '),
    latitude: lat,
    longitude: lng,
  };
}

export function nominatimPlace(
  body: Json,
  lat: number,
  lng: number,
): GeoPlace | null {
  const a = (body?.address ?? null) as Json | null;
  if (!a || text(a.country_code).toLowerCase() !== 'vn') return null;
  const house = text(a.house_number),
    road = text(a.road);
  const street = house && road ? `${house} ${road}` : road;
  const name = text(body.name);
  const title = join([name && name !== road ? name : '', street]).join(', ');
  const area = join([
    text(a.quarter) || text(a.suburb) || text(a.village) || text(a.hamlet),
    text(a.city_district),
    text(a.city) || text(a.town) || text(a.county),
    text(a.state),
  ]);
  const first = title || area.shift() || '';
  if (!first) return null;
  return {
    title: first,
    subtitle: area.join(', '),
    address: join([first, ...area]).join(', '),
    // The pin, not the matched building: the courier goes where it points.
    latitude: lat,
    longitude: lng,
  };
}
