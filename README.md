# WikiTruth Supabase 数据库

本文档说明如何设置和使用 WikiTruth 项目的 Supabase 数据库。

## 目录结构

```
supabase/
├── migrations/              # 数据库迁移文件
│   ├── 20240101000000_01_tables.sql      # 表结构定义
│   ├── 20240101000001_02_indexes.sql     # 索引定义
│   └── 20240101000002_03_functions.sql  # 全文搜索函数
├── config/                 # 配置文件
│   └── supabase.config.ts        # Supabase 连接配置
├── .env.example           # 环境变量模板
└── README.md              # 本文档
```

## 快速开始

### 1. 创建 Supabase 项目

1. 访问 [Supabase Dashboard](https://app.supabase.com/)
2. 创建新项目
3. 记录项目 URL 和 API Keys

### 2. 配置环境变量

1. 复制 `env.template` 为 `.env`
2. 填写 Supabase 项目配置：

```bash
SUPABASE_URL=https://xxxxxxxxxxxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### 3. 执行数据库迁移

#### 方式 A：使用 Supabase CLI（推荐）

```bash
# 安装 Supabase CLI
npm install -g supabase

# 登录 Supabase
supabase login

# 链接到项目
supabase link --project-ref your-project-ref

# 执行迁移
supabase db push
```

#### 方式 B：使用 Supabase Dashboard

1. 登录 [Supabase Dashboard](https://app.supabase.com/)
2. 进入项目 -> SQL Editor
3. 依次执行以下文件的内容：
   - `migrations/20240101000000_01_tables.sql`
   - `migrations/20240101000001_02_indexes.sql`
   - `migrations/20240101000002_03_functions.sql`

### 4. 配置客户端

1. 复制 `config/supabase.config.example.ts` 为 `config/supabase.config.ts`
2. 确保 `.env` 文件已配置
3. 在代码中使用：

```typescript
import { supabase } from './config/supabase.config';

// 查询示例
const { data, error } = await supabase
  .from('boxes')
  .select('*')
  .limit(10);
```

## 数据库结构

### 核心表

- **boxes** - Box 主表（链上事件数据）
- **metadata_boxes** - MetadataBox 关联表（IPFS 元数据）
- **users** - 用户表（UserId）
- **user_addresses** - 用户地址表（User2）

### 交易相关表

- **payments** - 支付记录表
- **withdraws** - 提取记录表
- **user_orders** - 用户订单表
- **reward_amounts** - 奖励金额表
- **user_rewards** - 用户奖励表
- **box_bidders** - Box 竞标者关联表

### 统计表

- **statistical_state** - 统计状态表（单例）
- **fund_manager_state** - 资金管理器状态表（单例）
- **token_total_amounts** - 代币总金额表（替代旧的 token_total_reward_amounts，支持 4 种类型：OrderDeposit、OrderWithdraw、RewardsAdded、RewardsWithdraw）

### 审计和同步表

- **events** - 事件原始数据表（可选）
- **sync_status** - 同步状态表（用于事件同步脚本）

## 全文搜索功能

### search_boxes 函数

支持全文搜索和复合筛选：

```typescript
const { data, error } = await supabase.rpc('search_boxes', {
  search_query: 'fraud ponzi',
  status_filter: ['Selling', 'Auctioning'],
  type_of_crime_filter: ['Financial Crime'],
  country_filter: ['Bolivia'],
  min_price: 1000000000000000000,
  max_price: 10000000000000000000,
  limit_count: 20,
  offset_count: 0
});
```

### search_boxes_by_label 函数

按标签搜索：

```typescript
const { data, error } = await supabase.rpc('search_boxes_by_label', {
  label_query: ['ponzi', 'fraud'],
  limit_count: 20,
  offset_count: 0
});
```

## 查询示例

### 关联查询

```typescript
// 查询 Box 及其元数据
const { data } = await supabase
  .from('boxes')
  .select(`
    *,
    metadata_box:metadata_boxes!inner (*)
  `)
  .eq('id', '123')
  .single();

// 查询 Box 及其所有关联数据
const { data } = await supabase
  .from('boxes')
  .select(`
    *,
    metadata_box:metadata_boxes!inner (*),
    payments (*),
    reward_amounts (*),
    minter:users!boxes_minter_id_fkey (*),
    owner:user_addresses!boxes_owner_address_fkey (*)
  `)
  .eq('id', '123')
  .single();
```

### 精确查询

```typescript
// 查询特定状态的 Box
const { data } = await supabase
  .from('boxes')
  .select('*')
  .eq('status', 'Selling')
  .order('create_timestamp', { ascending: false });

// 查询特定用户的 Box
const { data } = await supabase
  .from('boxes')
  .select('*')
  .eq('minter_id', '123')
  .order('create_timestamp', { ascending: false });
```

## 数据同步

数据通过 `eventSyncScript` 脚本从区块链同步到 Supabase：

1. 脚本从 Oasis Nexus API 获取区块链事件
2. 从 IPFS 获取 MetadataBox JSON 数据
3. 写入 `boxes` 和 `metadata_boxes` 表
4. 更新相关关联表和统计表

详细说明请参考 `eventSyncScript/eventSync需求.md`。

## 安全注意事项

1. **Service Role Key**：
   - 仅在服务端使用
   - 不要暴露给客户端
   - 不要提交到代码仓库

2. **Row Level Security (RLS)**：
   - 建议为表启用 RLS
   - 配置适当的访问策略
   - 参考需求文档中的 RLS 策略示例

3. **环境变量**：
   - `.env` 文件不要提交到代码仓库
   - 使用 `.env.example` 作为模板
   - 在生产环境使用安全的密钥管理服务

## 维护

### 更新数据库结构

1. 创建新的迁移文件：`migrations/YYYYMMDDHHMMSS_description.sql`
2. 使用 `CREATE OR REPLACE` 确保可重复执行
3. 测试迁移文件
4. 执行迁移

### 备份

Supabase 提供自动备份功能，建议：
- 定期检查备份状态
- 在重要变更前手动创建备份
- 保留迁移文件历史记录

## 故障排查

### 迁移失败

1. 检查 SQL 语法错误
2. 确认表依赖关系正确
3. 检查外键约束
4. 查看 Supabase Dashboard 的日志

### 查询性能问题

1. 检查索引是否创建
2. 使用 `EXPLAIN ANALYZE` 分析查询
3. 优化查询语句
4. 考虑添加复合索引

### 连接问题

1. 检查环境变量配置
2. 验证 Supabase URL 和 Key
3. 检查网络连接
4. 查看 Supabase Dashboard 的项目状态

## 测试

### 运行测试

1. **配置测试环境**：
   ```bash
   # 复制测试环境变量模板
   cp env.test.template .env.test
   # 编辑 .env.test，填写测试环境的 Supabase 配置
   ```

2. **安装测试依赖**：
   ```bash
   npm install
   ```

3. **运行测试**：
   ```bash
   # 运行所有测试
   npm test

   # 监听模式（开发时使用）
   npm run test:watch

   # 运行特定测试
   npm run test:migrations    # 迁移测试
   npm run test:network      # 网络隔离测试
   npm run test:search       # 搜索函数测试
   npm run test:crud         # CRUD 操作测试
   npm run test:types        # 类型定义测试

   # 生成覆盖率报告
   npm run test:coverage
   ```

### 测试文件说明

- `tests/migrations.test.ts` - 验证数据库迁移是否正确
- `tests/network-isolation.test.ts` - 验证网络划分功能
- `tests/search-functions.test.ts` - 验证搜索函数
- `tests/crud-operations.test.ts` - 验证 CRUD 操作
- `tests/foreign-keys.test.ts` - 验证外键约束
- `tests/unique-constraints.test.ts` - 验证唯一约束
- `tests/type-definitions.test.ts` - 验证 TypeScript 类型定义
- `tests/integration.test.ts` - 集成测试

详细测试说明请参考 `tests/README.md`。

## 参考文档

- [Supabase 官方文档](https://supabase.com/docs)
- [PostgreSQL 全文搜索](https://www.postgresql.org/docs/current/textsearch.html)
- [Supabase CLI 文档](https://supabase.com/docs/reference/cli/introduction)
- [Vitest 文档](https://vitest.dev/)

## 支持

如有问题，请参考：
- `supabase需求文档.md` - 详细的需求文档
- `eventSync需求.md` - 数据同步脚本说明
- `tests/README.md` - 测试说明文档

