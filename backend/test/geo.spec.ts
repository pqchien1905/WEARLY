import {
  GeoService,
  nominatimPlace,
  photonPlace,
} from '../src/modules/geo/geo.service';
import { ConfigService } from '@nestjs/config';

const config = (values: Record<string, string> = {}) =>
  ({
    get: (k: string) => values[k],
    getOrThrow: (k: string) =>
      values[k] ??
      {
        GEO_SUGGEST_URL: 'https://photon.test/api/',
        GEO_REVERSE_URL: 'https://nominatim.test/reverse',
      }[k],
  }) as unknown as ConfigService;
const json = (body: unknown) =>
  Promise.resolve(new Response(JSON.stringify(body), { status: 200 }));

const feature = (
  properties: Record<string, unknown>,
  lng = 106.7,
  lat = 10.77,
) => ({
  properties: { countrycode: 'VN', ...properties },
  geometry: { coordinates: [lng, lat] },
});

describe('address lookup formatting', () => {
  it('reads a building with its street in Vietnamese order', () => {
    expect(
      photonPlace(
        feature({
          name: 'Vincom Center Bà Triệu',
          housenumber: '191',
          street: 'Phố Bà Triệu',
          district: 'Hai Bà Trưng',
          city: 'Hà Nội',
        }),
      ),
    ).toEqual({
      title: 'Vincom Center Bà Triệu, 191 Phố Bà Triệu',
      subtitle: 'Hai Bà Trưng, Hà Nội',
      address: 'Vincom Center Bà Triệu, 191 Phố Bà Triệu, Hai Bà Trưng, Hà Nội',
      latitude: 10.77,
      longitude: 106.7,
    });
  });

  it('names a street by itself and drops places outside Vietnam', () => {
    expect(
      photonPlace(
        feature({
          type: 'street',
          name: 'Lê Duẩn',
          city: 'Vinh',
          state: 'Nghệ An',
        }),
      )?.address,
    ).toBe('Lê Duẩn, Vinh, Nghệ An');
    expect(
      photonPlace(feature({ countrycode: 'LA', name: 'Viêng Chăn' })),
    ).toBeNull();
    expect(photonPlace({ properties: { countrycode: 'VN' } })).toBeNull();
  });

  it('keeps the dropped pin, not the matched building, for the courier', () => {
    const place = nominatimPlace(
      {
        name: 'Hồ Gươm',
        address: {
          country_code: 'vn',
          house_number: '79',
          road: 'Phố Đinh Tiên Hoàng',
          quarter: 'Phường Hoàn Kiếm',
          city: 'Hà Nội',
        },
      },
      21.0285,
      105.8542,
    );
    expect(place).toEqual({
      title: 'Hồ Gươm, 79 Phố Đinh Tiên Hoàng',
      subtitle: 'Phường Hoàn Kiếm, Hà Nội',
      address: 'Hồ Gươm, 79 Phố Đinh Tiên Hoàng, Phường Hoàn Kiếm, Hà Nội',
      latitude: 21.0285,
      longitude: 105.8542,
    });
    expect(
      nominatimPlace({ address: { country_code: 'th' } }, 1, 1),
    ).toBeNull();
  });
});

describe('GeoService', () => {
  it('limits search to Vietnam, identifies itself and caches repeats', async () => {
    const http = jest.fn(() =>
      json({
        features: [feature({ name: 'Chợ Bến Thành', city: 'Hồ Chí Minh' })],
      }),
    );
    const service = new GeoService(config(), http as unknown as typeof fetch);
    const first = await service.suggest('  chợ   bến thành ', {
      lat: 10.77,
      lng: 106.7,
    });
    expect(first).toHaveLength(1);
    const [url, init] = http.mock.calls[0] as unknown as [URL, RequestInit];
    expect(url.searchParams.get('q')).toBe('chợ bến thành');
    expect(url.searchParams.get('bbox')).toBe('102.1,8.2,109.6,23.4');
    expect((init.headers as Record<string, string>)['User-Agent']).toBe(
      'WearlyShop/1.0',
    );
    await service.suggest('Chợ Bến Thành', { lat: 10.771, lng: 106.701 });
    expect(http).toHaveBeenCalledTimes(1);
    expect(await service.suggest('ab')).toEqual([]);
    expect(http).toHaveBeenCalledTimes(1);
  });

  it('reports the provider being down and can be turned off', async () => {
    const down = new GeoService(
      config(),
      jest.fn(() =>
        Promise.reject(new Error('offline')),
      ) as unknown as typeof fetch,
    );
    await expect(down.suggest('Nguyễn Huệ')).rejects.toMatchObject({
      status: 503,
    });
    const off = new GeoService(
      config({ GEO_ENABLED: 'false' }),
      jest.fn() as unknown as typeof fetch,
    );
    await expect(off.reverse(10.7, 106.7)).rejects.toMatchObject({
      status: 503,
    });
  });
});
