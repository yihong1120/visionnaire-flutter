import 'package:flutter/material.dart';

import '../../services/file_manage_api_service.dart';
import '../../utils/auth_utils.dart';
import '../../utils/signature_task_status.dart';
import '../../widgets/app_transitions.dart';
import '../../widgets/responsive_scaffold.dart';
import '../../l10n/app_localizations.dart';
import 'my_tasks_page.dart';
import 'sign_task_page.dart';

class SignTaskLaunchPage extends StatefulWidget {
  const SignTaskLaunchPage({
    super.key,
    this.taskId,
    this.documentId,
    this.versionId,
  });

  final int? taskId;
  final int? documentId;
  final int? versionId;

  @override
  State<SignTaskLaunchPage> createState() => _SignTaskLaunchPageState();
}

class _SignTaskLaunchPageState extends State<SignTaskLaunchPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _targetTask;

  int _taskVersion(Map<String, dynamic> task) {
    return (task['version_id'] as num?)?.toInt() ?? 0;
  }

  int _taskId(Map<String, dynamic> task) {
    return (task['task_id'] as num?)?.toInt() ?? 0;
  }

  String _taskStatus(Map<String, dynamic> task) {
    return normalizeSignatureTaskStatus(task['status'] as String?);
  }

  bool _isActiveTask(Map<String, dynamic> task) {
    return isActionableSignatureTaskStatus(_taskStatus(task));
  }

  Map<String, dynamic>? _pickLatestTaskForDocument(
    List<Map<String, dynamic>> tasks,
    int documentId,
  ) {
    final List<Map<String, dynamic>> candidates = tasks.where((task) {
      final int? taskDocumentId = (task['document_id'] as num?)?.toInt();
      return taskDocumentId == documentId && _isActiveTask(task);
    }).toList()
      ..sort((a, b) {
        final int byVersion = _taskVersion(b).compareTo(_taskVersion(a));
        if (byVersion != 0) {
          return byVersion;
        }
        return _taskId(b).compareTo(_taskId(a));
      });

    return candidates.isEmpty ? null : candidates.first;
  }

  @override
  void initState() {
    super.initState();
    _loadTargetTask();
  }

  Future<void> _loadTargetTask() async {
    setState(() {
      _loading = true;
      _error = null;
      _targetTask = null;
    });

    try {
      Map<String, dynamic>? matchedTask;
      List<Map<String, dynamic>> myTasks = <Map<String, dynamic>>[];

      if (widget.taskId != null) {
        final Map<String, dynamic> fetchedTask = await AuthUtils.withAuthRetry(
          context,
          (token) => FileManageAPIService.getSingleSignTask(
            token: token,
            taskId: widget.taskId!,
          ),
        );
        if (!mounted) return;
        matchedTask = fetchedTask;

        final int? documentId = (fetchedTask['document_id'] as num?)?.toInt();
        if (documentId != null) {
          myTasks = await AuthUtils.withAuthRetry(
            context,
            (token) => FileManageAPIService.getMySignTasks(token: token),
          );
          final Map<String, dynamic>? latestTask =
              _pickLatestTaskForDocument(myTasks, documentId);
          if (latestTask != null &&
              _taskVersion(latestTask) > _taskVersion(fetchedTask)) {
            matchedTask = latestTask;
          } else if (!_isActiveTask(fetchedTask)) {
            matchedTask = null;
          }
        }
      } else if (widget.documentId != null) {
        myTasks = await AuthUtils.withAuthRetry(
          context,
          (token) => FileManageAPIService.getMySignTasks(token: token),
        );

        matchedTask = _pickLatestTaskForDocument(myTasks, widget.documentId!);

        if (matchedTask == null && widget.versionId != null) {
          final List<Map<String, dynamic>> exactVersionMatches =
              myTasks.where((task) {
            final int? taskDocumentId = (task['document_id'] as num?)?.toInt();
            final int? taskVersionId = (task['version_id'] as num?)?.toInt();
            return taskDocumentId == widget.documentId &&
                taskVersionId == widget.versionId;
          }).toList()
                ..sort((a, b) => _taskId(b).compareTo(_taskId(a)));

          if (exactVersionMatches.isNotEmpty) {
            matchedTask = exactVersionMatches.first;
          }
        }
      }

      if (!mounted) return;
      if (matchedTask == null) {
        setState(() {
          _loading = false;
          _error = AppLocalizations.of(context)!.signTaskNotFound;
        });
        return;
      }

      setState(() {
        _targetTask = matchedTask;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context)!.loadSignTaskFailed(e.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ResponsiveScaffold(
        title: AppLocalizations.of(context)!.signDocument,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return ResponsiveScaffold(
        title: AppLocalizations.of(context)!.signDocument,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.assignment_late_outlined, size: 48),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loadTargetTask,
                  child: Text(AppLocalizations.of(context)!.tryAgain),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    pushReplacementAppPage<void, void>(
                      context,
                      builder: (_) => const MyTasksPage(),
                    );
                  },
                  child: Text(AppLocalizations.of(context)!.goToMyTasks),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final Map<String, dynamic> task = _targetTask!;
    return SignTaskPage(
      taskId: task['task_id'] as int,
      versionId: task['version_id'] as int,
      documentId: task['document_id'] as int,
      initialStatus: task['status'] as String? ?? 'pending',
      initialComment: task['comment'] as String? ?? '',
    );
  }
}
