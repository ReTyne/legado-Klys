/// 第十轮（v14）新增数据实体 barrel。
///
/// 对齐 legado-E `data/entities/`：一类一文件，拆分到 `lib/data/entities/`。
/// 本文件仅做 re-export，保持历史 import 路径不变。
library;

export '../entities/search_book_table.dart';
export '../entities/book_source_check_state.dart';
export '../entities/pdf_outline.dart';
export '../entities/page_estimate.dart';
export '../entities/kv_cache.dart';
export '../entities/book_review.dart';
export '../entities/read_preset.dart';
export '../entities/danmaku_cache.dart';
export '../entities/bgm_track.dart';
export '../entities/ai_agent_tool.dart';
