import { IsBoolean, IsInt, Min } from 'class-validator';
export class OrderClassificationDto {
  @IsBoolean() isTest!: boolean;
  @IsInt() @Min(0) expectedVersion!: number;
}
