FROM node:24-bookworm-slim AS base
RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app

FROM base AS build
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Operational tooling is a separate, short-lived image, never the API runtime.
FROM build AS migration
USER node
CMD ["npm", "run", "prisma:deploy"]

FROM build AS production-deps
# Ignore optional peer edges only while pruning the already-built tree:
# Prisma otherwise retains its devOptional CLI/TypeScript. Required runtime
# peers (rxjs, reflect-metadata, etc.) are declared as direct dependencies.
RUN npm prune --omit=dev --legacy-peer-deps --ignore-scripts

FROM base AS runtime
ENV NODE_ENV=production
COPY --from=production-deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/package*.json ./
USER node
EXPOSE 3000
CMD ["node", "dist/main.js"]
