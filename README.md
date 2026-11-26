# deliver-kit — 内部文档问答系统的交付包

开发把代码写完只是开始。现场真正卡人的是三件事：

1. **装不上**——Python 版本不对、依赖没装、端口被占、密钥没配，每样都要试半天
2. **验收没标准**——客户问「准不准」，你答「召回率 96.7%」，客户听不懂
3. **出问题查不出**——客户只会截图，你要么远程半小时，要么让对方贴日志（还贴错）

这个包把这三件事变成四个命令。

## 四个命令

```powershell
# 1) 自检：装得成吗、跑得起来吗（退出码 0 通过 / 1 有项没过）
powershell -ExecutionPolicy Bypass -File .\scripts\check.ps1

# 2) 验收：把用例打给服务，出可签字的报告
python scripts\accept.py --url http://127.0.0.1:8000

# 3) 收现场：环境快照 + 脱敏配置 + 依赖 + 日志 → 一个 zip
powershell -ExecutionPolicy Bypass -File .\scripts\diagnose.ps1

# 4) 换客户：只改 config，不改代码
config\customer-a.json
```

## 自检输出（真实）

```
== 交付前自检 ==
[OK]   配置文件           端口 8000，模型 glm-4-air
[OK]   Python         Python 3.12.14
[OK]   fastapi        已安装
[OK]   uvicorn        已安装
[OK]   模型密钥           已配置（长度 49）
[OK]   端口 8000        空闲
[OK]   知识库索引          1704 KB
[OK]   模型接口           https://open.bigmodel.cn/api/paas/v4 通（223 ms，13 个模型）

结论：全部通过，可以部署。
```

## 验收报告（真实，含一次翻车与修复）

首轮 7 条只过 5 条：

| # | 问题 | 期望 | 结果 | 回答 |
|---|---|---|---|---|
| 4 | 企业知识库问答系统的 recall@5 是多少？ | 应回答 | ❌ | 资料中没有找到相关内容。 |
| 5 | 自然语言数据分析 Agent 的 SQL 通过率是多少？ | 应回答 | ❌ | ……首次执行成功率【A】% |

追下去发现**知识库里放的是旧版文档**，数字还是占位符 `【A】`。更新语料 → 重新 `ingest`（17 文档 / 274 片，2.9 s）→ 重启服务 → 二轮：

```
用例数：7　通过：7　通过率：100.0%
平均响应：876 ms
```

这就是验收存在的意义：**不跑一遍，你永远不知道客户拿到的是哪一版。**

## 排障包

`diagnose.ps1` 产出 `排障包-<时间>.zip`：

- `环境快照.json`（系统 / 硬件 / 运行时 / 网络 / 端口）
- `配置-脱敏.json`（密钥只留前 4 位）
- `pip-freeze.txt`、`最近日志.txt`（最后 300 行）、`服务状态.txt`、`health.json`

客户发 zip，不用截图、不用教对方怎么找日志。

## 目录

```
deliver-kit\
  config\customer-a.json     客户配置（端口 / apiBase / 密钥文件 / 索引 / 依赖目录）
  scripts\check.ps1          部署前自检（8 项，带退出码）
  scripts\accept.py          验收（用例 jsonl 可换，出 Markdown 报告）
  scripts\diagnose.ps1       现场收集
  scripts\ping_model.py      探模型连通性（PowerShell 的 TLS 在部分客户机不可靠，改用 Python）
  scripts\cases.jsonl        验收用例：5 条应回答 + 2 条应拒答
  交付手册.md                 现场手册：四个动作 + 常见问题表 + 真实交付过程
```

## 限制

- `check.ps1` 依赖 Windows PowerShell 5.1，脚本必须是 **UTF-8 with BOM**，否则中文会按 GBK 解析报错
- `accept.py` 只判「是否拒答 / 是否包含关键词」，不做语义判分（那是评测集的事）
- 验收用例需要按客户语料重写，包里这 7 条对应的是我自己的知识库
