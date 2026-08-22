// lib/pages/my_tasks_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/file_manage_api_service.dart';
import '../../widgets/app_transitions.dart';
import '../../widgets/responsive_scaffold.dart';
import '../../utils/auth_utils.dart';
import '../../utils/signature_task_status.dart';
import '../../l10n/app_localizations.dart';
import 'sign_task_page.dart';

class MyTasksPage extends StatefulWidget {
  const MyTasksPage({
    super.key,
    this.openDocumentId,
    this.openVersionId,
  });

  /// 若從推播深連結進入，完成載入後自動開啟此 document ID 對應的任務。
  final int? openDocumentId;

  /// 可進一步限定 version ID（選填；null 表示符合任意版本）。
  final int? openVersionId;

  @override
  State<MyTasksPage> createState() => _MyTasksPageState();
}

class _MyTasksPageState extends State<MyTasksPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _tasks = [];
  Map<int, Map<String, dynamic>> _fileDetailsByDocumentId =
      <int, Map<String, dynamic>>{};
  String? _error;
  bool _autoOpenedInitialTask = false;
  final DateFormat _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  bool _isActiveTask(Map<String, dynamic> task) {
    return isActionableSignatureTaskStatus(task['status'] as String?);
  }

  int? _taskDocumentId(Map<String, dynamic> task) {
    return (task['document_id'] as num?)?.toInt();
  }

  Map<String, dynamic>? _taskFileDetail(Map<String, dynamic> task) {
    final int? documentId = _taskDocumentId(task);
    if (documentId == null) return null;
    return _fileDetailsByDocumentId[documentId];
  }

  String _firstNonEmptyText(Iterable<dynamic> values) {
    for (final dynamic value in values) {
      final String text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return '';
  }

  String _firstNonEmptyString(Iterable<dynamic> values) {
    for (final dynamic value in values) {
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  String _taskText(Map<String, dynamic> task, List<String> keys) {
    final Map<String, dynamic>? detail = _taskFileDetail(task);
    return _firstNonEmptyText(<dynamic>[
      for (final String key in keys) task[key],
      if (detail != null) ...<dynamic>[
        for (final String key in keys) detail[key],
      ],
    ]);
  }

  String _taskCreatorText(Map<String, dynamic> task) {
    final Map<String, dynamic>? detail = _taskFileDetail(task);
    return _firstNonEmptyString(<dynamic>[
      task['creator_name'],
      task['creator_username'],
      task['created_by_name'],
      task['created_by_username'],
      task['creator'],
      if (detail != null) ...<dynamic>[
        detail['creator_name'],
        detail['creator_username'],
        detail['created_by_name'],
        detail['created_by_username'],
        detail['creator'],
      ],
    ]);
  }

  String _formatDateTimeText(dynamic value) {
    final String raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '';
    final DateTime? parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return _dateFmt.format(parsed);
  }

  String _taskTitle(Map<String, dynamic> task, AppLocalizations l) {
    final String site = _taskText(task, <String>['site_name']);
    final String code = _taskText(task, <String>[
      'full_file_code',
      'document_name',
      'file_name',
      'name',
    ]);
    final String docType = _taskText(task, <String>['document_type_name']);
    final String title = <String>[code, docType]
        .where((String value) => value.isNotEmpty)
        .join(' · ');
    if (site.isNotEmpty && title.isNotEmpty) {
      return '[$site] $title';
    }
    if (title.isNotEmpty) {
      return title;
    }
    return _taskSignatureContext(task, l);
  }

  String _taskSignatureContext(Map<String, dynamic> task, AppLocalizations l) {
    final String version = _firstNonEmptyText(<dynamic>[task['version_id']]);
    final String placeholder = _taskText(task, <String>[
      'placeholder_name',
      'placeholder_label',
      'placeholder_title',
      'placeholder',
      'placeholder_text',
      'placeholder_id',
    ]);
    if (version.isNotEmpty && placeholder.isNotEmpty) {
      return l.versionPlaceholder(version, placeholder);
    }
    if (placeholder.isNotEmpty) {
      return placeholder;
    }
    return l.versionPlaceholder(
      version.isEmpty ? '-' : version,
      _firstNonEmptyText(<dynamic>[task['placeholder_id'], '-']),
    );
  }

  Future<Map<int, Map<String, dynamic>>> _loadTaskFileDetails(
    String token,
    List<Map<String, dynamic>> tasks,
  ) async {
    final Set<int> documentIds = <int>{
      for (final Map<String, dynamic> task in tasks)
        if (_taskDocumentId(task) case final int documentId) documentId,
    };
    if (documentIds.isEmpty) {
      return <int, Map<String, dynamic>>{};
    }

    final Map<int, Map<String, dynamic>> details =
        <int, Map<String, dynamic>>{};
    await Future.wait(documentIds.map((int documentId) async {
      try {
        details[documentId] = await FileManageAPIService.getFileById(
          token: token,
          fileId: documentId,
        );
      } catch (_) {
        // A task remains usable without its optional document summary.
      }
    }));

    return details;
  }

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> payload = await AuthUtils.withAuthRetry(
        context,
        (token) async {
          final List<Map<String, dynamic>> tasks =
              await FileManageAPIService.getMySignTasks(token: token);
          final List<Map<String, dynamic>> activeTasks =
              tasks.where(_isActiveTask).toList();
          final Map<int, Map<String, dynamic>> details =
              await _loadTaskFileDetails(token, activeTasks);
          return <String, dynamic>{
            'tasks': activeTasks,
            'details': details,
          };
        },
      );
      _tasks = List<Map<String, dynamic>>.from(
        payload['tasks'] as List<Map<String, dynamic>>,
      );
      _fileDetailsByDocumentId = Map<int, Map<String, dynamic>>.from(
        payload['details'] as Map<int, Map<String, dynamic>>,
      );
      // 深連結：從推播帶入 document_id 時，自動找到對應任務並開啟
      if (mounted && widget.openDocumentId != null && !_autoOpenedInitialTask) {
        await _autoOpenMatchingTask();
      }
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 在任務清單中尋找符合 [openDocumentId]（及選填的 [openVersionId]）的任務，
  /// 並在下一幀自動推入 [SignTaskPage]。
  Future<void> _autoOpenMatchingTask() async {
    Map<String, dynamic>? target;
    for (final task in _tasks) {
      if (task['document_id'] == widget.openDocumentId) {
        if (widget.openVersionId == null ||
            task['version_id'] == widget.openVersionId) {
          target = task;
          break;
        }
      }
    }
    if (target == null) return;
    _autoOpenedInitialTask = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final bool? ok = await pushAppPage<bool>(
        context,
        builder: (_) => SignTaskPage(
          taskId: target!['task_id'] as int,
          versionId: target['version_id'] as int,
          documentId: target['document_id'] as int,
          initialStatus: target['status'] as String,
          initialComment: target['comment'] as String,
        ),
      );
      if (!mounted) return;
      if (ok == true) {
        await _loadTasks();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      title: AppLocalizations.of(context)!.mySignTasks,
      isFullscreen: true,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child:
                      Text(AppLocalizations.of(context)!.errorPrefix(_error!)))
              : _tasks.isEmpty
                  ? Center(
                      child: Text(AppLocalizations.of(context)!.noSignTasks))
                  : RefreshIndicator(
                      onRefresh: _loadTasks,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        itemCount: _tasks.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final t = _tasks[index];
                          final AppLocalizations l =
                              AppLocalizations.of(context)!;
                          final String statusLabel = signatureTaskStatusLabel(
                            t['status'] as String?,
                            l,
                          );
                          final String comment =
                              (t['comment'] as String? ?? '').trim();
                          final String createdAt = _formatDateTimeText(
                            _taskText(t, <String>['created_at']),
                          );
                          final String updatedAt = _formatDateTimeText(
                            _taskText(t, <String>['updated_at']),
                          );
                          final String docType =
                              _taskText(t, <String>['document_type_name']);
                          final String creator = _taskCreatorText(t);
                          final String site =
                              _taskText(t, <String>['site_name']);
                          final String taskSummary = l.taskNumberStatus(
                            _firstNonEmptyText(<dynamic>[t['task_id']]),
                            statusLabel,
                          );

                          return Card(
                            margin: EdgeInsets.zero,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                await pushAppPage<bool>(
                                  context,
                                  builder: (_) => SignTaskPage(
                                    taskId: t['task_id'] as int,
                                    versionId: t['version_id'] as int,
                                    documentId: t['document_id'] as int,
                                    initialStatus: t['status'] as String,
                                    initialComment: t['comment'] as String,
                                  ),
                                );
                                if (!mounted) return;
                                await _loadTasks();
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _taskTitle(t, l),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                _taskSignatureContext(t, l),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        _MyTaskStatusBadge(
                                          statusLabel: statusLabel,
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(
                                          Icons.arrow_forward_ios,
                                          size: 16,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (docType.isNotEmpty)
                                          _MyTaskMetaChip(
                                            icon: Icons.description_outlined,
                                            text: docType,
                                          ),
                                        if (site.isNotEmpty)
                                          _MyTaskMetaChip(
                                            icon: Icons.place_outlined,
                                            text: site,
                                          ),
                                        if (creator.isNotEmpty)
                                          _MyTaskMetaChip(
                                            icon: Icons.person_outline,
                                            text: '${l.creatorLabel}: $creator',
                                          ),
                                        if (createdAt.isNotEmpty)
                                          _MyTaskMetaChip(
                                            icon: Icons.schedule,
                                            text:
                                                '${l.createdTime}: $createdAt',
                                          ),
                                        if (updatedAt.isNotEmpty)
                                          _MyTaskMetaChip(
                                            icon: Icons.update,
                                            text:
                                                '${l.lastUpdated}: $updatedAt',
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      taskSummary,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                    if (comment.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          l.commentLabel(comment),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _MyTaskStatusBadge extends StatelessWidget {
  const _MyTaskStatusBadge({required this.statusLabel});

  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        statusLabel,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: cs.onTertiaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _MyTaskMetaChip extends StatelessWidget {
  const _MyTaskMetaChip({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}
