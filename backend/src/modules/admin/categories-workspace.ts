import { PrismaService } from '../../database/prisma.service';
import { AdminCategoriesQueryDto } from './dto/admin-categories-query.dto';
import {
  taxonomyList,
  taxonomySummary,
  taxonomyDetail,
} from './taxonomy-workspace';
export const categoryList = (db: PrismaService, q: AdminCategoriesQueryDto) =>
  taxonomyList(db, 'categories', q);
export const categorySummary = (db: PrismaService) =>
  taxonomySummary(db, 'categories');
export const categoryDetail = (db: PrismaService, id: string) =>
  taxonomyDetail(db, 'categories', id);
