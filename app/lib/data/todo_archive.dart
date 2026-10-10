// app/lib/data/todo_archive.dart
//
// 「已完成」的待办收进列表底部的折叠区 —— 这个文件只放两件与界面无关的东西：
//   · 把一串待办拆成「主列表」与「折叠区」两批（纯函数，好单测）；
//   · 归档上限那个数字。
//
// 为什么放 `data/` 而不是 `domain/`：`ScheduleEvent` 是 drift 生成的行类，而
// `domain/` 到现在为止不依赖数据层 —— 别为一个拆列表的函数破那个界限。
import 'app_database.dart';

/// 折叠区里最多留多少条已完成的待办，超出的按日期从旧到新丢掉。
///
/// **这不是一个设置项** —— 100 是用户点名要的值（2026-10-11 反馈原话：「归档数
/// 可以设成 100 条」）。做成开关只会多一处要维护的状态。截断的时机在 `home_shell`
/// 的启动就绪闸里（理由见 `AppRepository.pruneArchivedTodos` 的注释）。
const int kArchivedTodoLimit = 100;

/// 一串待办拆成两批的结果。
class TodoSplit {
  const TodoSplit({required this.active, required this.archived});

  /// 主列表：未完成的，**加上本次进来之后刚勾掉的**。
  final List<ScheduleEvent> active;

  /// 折叠区：其余已完成的。
  final List<ScheduleEvent> archived;
}

/// 把 [events] 拆成主列表与折叠区。[justCompleted] 是「本次进来之后刚勾掉的行 id」。
///
/// **`active` 保持入参顺序**（`watchEvents()` 的日期升序）：刚勾的那条于是停在它
/// 原来的位置上、只是多了条删除线 —— 而不是「啪」地跳到列表末尾。
///
/// **`archived` 按日期降序**：这一区是「回头看一眼之前干完了什么」，不是「从头
/// 读到尾」，最近做完的该排最前。同一天按 id 降序兜底，顺序才是确定的。
TodoSplit splitTodos(List<ScheduleEvent> events, Set<int> justCompleted) {
  final active = <ScheduleEvent>[];
  final archived = <ScheduleEvent>[];
  for (final e in events) {
    if (!e.isCompleted || justCompleted.contains(e.id)) {
      active.add(e);
    } else {
      archived.add(e);
    }
  }
  archived.sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    return byDate != 0 ? byDate : b.id.compareTo(a.id);
  });
  return TodoSplit(active: active, archived: archived);
}
