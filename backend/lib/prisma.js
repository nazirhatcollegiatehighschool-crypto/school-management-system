// Prisma Client SINGLETON.
// One PrismaClient = one connection pool. Creating a new instance per
// request/file exhausts the Postgres connection limit on serverless, so the
// client is cached on globalThis across hot reloads and module re-evaluations.
const { PrismaClient } = require('@prisma/client');

const globalForPrisma = globalThis;

const prisma =
  globalForPrisma.__prisma ||
  new PrismaClient({
    log: process.env.NODE_ENV === 'production' ? ['error'] : ['warn', 'error'],
  });

if (process.env.NODE_ENV !== 'production') globalForPrisma.__prisma = prisma;

module.exports = prisma;
