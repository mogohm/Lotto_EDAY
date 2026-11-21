import { Body, Controller, Get, HttpCode, Param, Patch, Post, Query } from '@nestjs/common';
import { DrawStatus, LotteryKind } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize, IsArray, IsBoolean, IsDateString, IsIn, IsInt, IsObject, IsOptional, IsString, Matches, Max, MaxLength, Min,
} from 'class-validator';
import { AuthUser, ClientIp, CurrentUser, Public, RequirePerms } from './common/auth';
import { LotteryService } from './lottery.service';

class CreateDrawDto {
  @IsString() @Matches(/^[a-z][a-z0-9-]{1,30}$/) marketId!: string;
  @IsDateString() date!: string;
  @IsOptional() @Matches(/^([01]\d|2[0-3]):[0-5]\d$/) openTime?: string;
  @IsOptional() @Matches(/^([01]\d|2[0-3]):[0-5]\d$/) closeTime?: string;
}
class BulkDrawDto {
  @IsString() marketId!: string;
  @Type(() => Number) @IsInt() @Min(1) @Max(31) days!: number;
}
class SaveResultDto {
  @IsObject() results!: Record<string, string>;
  @IsOptional() @IsString() @MaxLength(500) sourceNote?: string;
  @IsOptional() @IsString() @MaxLength(120) sourceName?: string;
  @IsOptional() @IsString() @MaxLength(500) sourceUrl?: string;
  @IsOptional() @IsString() sourceCapturedAt?: string;
  @IsString() expectedVersion!: string;
}
class VersionDto {
  @IsOptional() @Type(() => Number) @IsInt() expectedVersion?: number;
  @IsOptional() @IsString() @MaxLength(500) note?: string;
}
class ScheduleDto {
  @IsOptional() @IsDateString() opensAt?: string;
  @IsOptional() @IsDateString() closesAt?: string;
  @Type(() => Number) @IsInt() expectedVersion!: number;
}
const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;
class MarketDto {
  @IsOptional() @IsString() @Matches(/^[a-z][a-z0-9-]{1,30}$/) id?: string;
  @IsOptional() @IsString() @MaxLength(80) nameTh?: string;
  @IsOptional() @IsString() @MaxLength(80) nameEn?: string;
  @IsOptional() @IsIn(Object.values(LotteryKind)) kind?: LotteryKind;
  @IsOptional() @IsString() @MaxLength(500) description?: string;
  @IsOptional() @IsArray() @ArrayMaxSize(3) @IsInt({ each: true }) allowedDigits?: number[];
  @IsOptional() @IsArray() @ArrayMaxSize(4) @IsString({ each: true }) allowedPositions?: string[];
  @IsOptional() @IsBoolean() enabled?: boolean;
  @IsOptional() @Matches(TIME) openTime?: string;
  @IsOptional() @Matches(TIME) closeTime?: string;
  @IsOptional() @Matches(TIME) resultTime?: string;
  @IsOptional() @IsArray() @ArrayMaxSize(7) @IsInt({ each: true }) drawWeekdays?: number[];
  @IsOptional() @IsInt() ticketPrice?: number;
  @IsOptional() @IsInt() sortOrder?: number;
  @IsOptional() @IsInt() expectedVersion?: number;
}

/** Public read endpoints (no auth). */
@Controller('lottery')
export class LotteryController {
  constructor(private readonly service: LotteryService) {}

  @Public() @Get('markets') markets() { return this.service.markets(); }
  @Public() @Get('draws') draws(@Query('marketId') marketId?: string) { return this.service.publicDraws(marketId); }
  @Public() @Get('published') published(@Query('marketId') marketId?: string) { return this.service.published(marketId); }
  @Public() @Get('check') check(@Query('number') number: string, @Query('drawId') drawId?: string, @Query('marketId') marketId?: string) {
    return this.service.check(number ?? '', drawId, marketId);
  }

  // ----- V3 legacy admin routes (kept for compatibility; now protected by JWT + RBAC instead of the demo key) -----
  @RequirePerms('markets.manage') @Post('admin/seed') seed() { return this.service.seedMarkets(); }
  @RequirePerms('draws.manage') @Post('admin/draws') create(@CurrentUser() u: AuthUser, @Body() dto: CreateDrawDto, @ClientIp() ip: string) {
    return this.service.createDraw(dto.marketId, dto.date, u, dto, ip);
  }
  @RequirePerms('results.edit') @Patch('admin/draws/:id/draft') save(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() dto: SaveResultDto, @ClientIp() ip: string) {
    return this.service.saveDraft(id, dto, u, ip);
  }
  @RequirePerms('results.edit') @Post('admin/draws/:id/generate-demo') @HttpCode(200) generate(@CurrentUser() u: AuthUser, @Param('id') id: string, @ClientIp() ip: string) {
    return this.service.generateDemo(id, u, ip);
  }
  @RequirePerms('results.edit', 'results.review', 'results.publish') @Post('admin/draws/:id/publish-demo') @HttpCode(200)
  publishDemo(@CurrentUser() u: AuthUser, @Param('id') id: string, @ClientIp() ip: string) { return this.service.publishDemo(id, u, ip); }
}

/** Admin lottery management. */
@Controller('admin/lottery')
export class LotteryAdminController {
  constructor(private readonly service: LotteryService) {}

  @RequirePerms('dashboard.view') @Get('markets') markets() { return this.service.markets(true); }
  @RequirePerms('markets.manage') @Post('markets') createMarket(@CurrentUser() u: AuthUser, @Body() dto: MarketDto, @ClientIp() ip: string) { return this.service.createMarket(dto, u, ip); }
  @RequirePerms('markets.manage') @Patch('markets/:id') updateMarket(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() dto: MarketDto, @ClientIp() ip: string) {
    return this.service.updateMarket(id, dto, u, ip);
  }

  @RequirePerms('dashboard.view') @Get('draws')
  draws(@Query('marketId') marketId?: string, @Query('status') status?: DrawStatus, @Query('from') from?: string, @Query('to') to?: string) {
    return this.service.draws({ marketId, status: status && Object.values(DrawStatus).includes(status) ? status : undefined, from, to });
  }
  @RequirePerms('dashboard.view') @Get('draws/:id') draw(@Param('id') id: string) { return this.service.draw(id); }
  @RequirePerms('draws.manage') @Post('draws') create(@CurrentUser() u: AuthUser, @Body() dto: CreateDrawDto, @ClientIp() ip: string) {
    return this.service.createDraw(dto.marketId, dto.date, u, dto, ip);
  }
  @RequirePerms('draws.manage') @Post('draws/bulk') bulk(@CurrentUser() u: AuthUser, @Body() dto: BulkDrawDto, @ClientIp() ip: string) {
    return this.service.createUpcoming(dto.marketId, dto.days, u, ip);
  }
  @RequirePerms('draws.manage') @Patch('draws/:id/schedule') schedule(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() dto: ScheduleDto, @ClientIp() ip: string) {
    return this.service.updateSchedule(id, dto, u, ip);
  }
  @RequirePerms('results.edit') @Patch('draws/:id/draft') save(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() dto: SaveResultDto, @ClientIp() ip: string) {
    return this.service.saveDraft(id, dto, u, ip);
  }
  @RequirePerms('results.edit') @Post('draws/:id/generate-demo') @HttpCode(200) generate(@CurrentUser() u: AuthUser, @Param('id') id: string, @ClientIp() ip: string) {
    return this.service.generateDemo(id, u, ip);
  }
  @RequirePerms('results.edit') @Post('draws/:id/submit') @HttpCode(200) submit(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() dto: VersionDto, @ClientIp() ip: string) {
    return this.service.submit(id, u, dto.expectedVersion, ip);
  }
  @RequirePerms('results.review') @Post('draws/:id/approve') @HttpCode(200) approve(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() dto: VersionDto, @ClientIp() ip: string) {
    return this.service.approve(id, u, dto.expectedVersion, dto.note, ip);
  }
  @RequirePerms('results.review') @Post('draws/:id/reject') @HttpCode(200) reject(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() dto: VersionDto, @ClientIp() ip: string) {
    return this.service.reject(id, u, dto.note ?? '', dto.expectedVersion, ip);
  }
  @RequirePerms('results.publish') @Post('draws/:id/publish') @HttpCode(200) publish(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() dto: VersionDto, @ClientIp() ip: string) {
    return this.service.publish(id, u, dto.expectedVersion, ip);
  }
  @RequirePerms('draws.manage') @Post('draws/:id/cancel') @HttpCode(200) cancel(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() dto: VersionDto, @ClientIp() ip: string) {
    return this.service.cancel(id, u, dto.note ?? '', dto.expectedVersion, ip);
  }
}
