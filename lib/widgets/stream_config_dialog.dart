import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../services/management_api_service.dart';
import '../utils/auth_utils.dart';

/// A dialog for editing the stream configuration of a single site.
///
/// Allows viewing, adding, editing, and deleting stream configs for a site, with full validation and backend integration.
class StreamConfigDialog extends StatefulWidget {
  /// The site object for which to edit stream configs.
  ///
  /// Only 'id' and 'name' are required. Authorization and group ownership must
  /// be resolved by the backend from the authenticated user and site id.
  final Map site;

  /// Creates a [StreamConfigDialog] for the given [site].
  const StreamConfigDialog({super.key, required this.site});

  @override
  State<StreamConfigDialog> createState() => _StreamConfigDialogState();
}

/// State for [StreamConfigDialog]. Handles all logic for loading, editing, and saving stream configs.
class _StreamConfigDialogState extends State<StreamConfigDialog> {
  // Backend data
  bool _loading = true;
  String? _error;
  int? _maxStreams;
  int _usedStreams = 0;
  List<dynamic> _currentConfigs = <dynamic>[];

  /// Mapping of detection boolean fields to their display names.
  Map<String, String> _getDetectionMap(BuildContext context) => {
        'detect_no_safety_vest_or_helmet':
            AppLocalizations.of(context)!.noSafetyVestOrHelmet,
        'detect_near_machinery_or_vehicle':
            AppLocalizations.of(context)!.nearMachineryOrVehicle,
        'detect_in_restricted_area':
            AppLocalizations.of(context)!.inRestrictedArea,
        'detect_in_utility_pole_restricted_area':
            AppLocalizations.of(context)!.inUtilityPoleArea,
        'detect_machinery_close_to_pole':
            AppLocalizations.of(context)!.machineryNearPole,
      };

  /// Builds a group of toggle switches for detection options.
  Widget _buildToggleGroup(
    BuildContext context,
    Map<String, bool> map,
    void Function(void Function()) setStateFn,
  ) {
    final detMap = _getDetectionMap(context);
    return Column(
      children: detMap.entries
          .map(
            (MapEntry<String, String> e) => SwitchListTile(
              dense: true,
              title: Text(e.value),
              value: map[e.key]!,
              onChanged: (bool v) => setStateFn(() => map[e.key] = v),
            ),
          )
          .toList(),
    );
  }

  // Form keys and controllers for adding a new stream config
  final GlobalKey<FormState> _newFormKey = GlobalKey<FormState>();
  final TextEditingController _newNameCtl = TextEditingController();
  final TextEditingController _newUrlCtl = TextEditingController();
  String _newModelKey = 'yolo26n';
  final Map<String, bool> _newDetect = <String, bool>{
    'detect_no_safety_vest_or_helmet': false,
    'detect_near_machinery_or_vehicle': false,
    'detect_in_restricted_area': false,
    'detect_in_utility_pole_restricted_area': false,
    'detect_machinery_close_to_pole': false,
  };
  // This gate decides whether the configured stream may run recognition or
  // appear on the live monitor wall.
  bool _newRecognitionEnabled = true;
  int _newStartHour = 7;
  int _newEndHour = 18;
  DateTime? _newExpireDate;

  static const List<String> _modelOptions = <String>[
    'yolo26n',
    'yolo26s',
    'yolo26m',
    'yolo26l',
    'yolo26x',
  ];
  static final List<int> _hourOptions =
      List<int>.generate(24, (int i) => i); // 0‒23

  /// Shows a date picker and calls [onPicked] with the selected date.
  Future<void> _pickDate({
    required DateTime? current,
    required void Function(DateTime?) onPicked,
    required BuildContext ctx,
  }) async {
    final DateTime today = DateTime.now();
    // If current is in the past, use today to avoid assertion error.
    final DateTime initial =
        (current != null && !current.isBefore(today)) ? current : today;

    final DateTime? picked = await showDatePicker(
      context: ctx,
      initialDate: initial,
      firstDate: today, // Only allow future dates
      lastDate: DateTime(today.year + 5),
    );
    if (picked != null) onPicked(picked);
  }

  /// Saves a new stream config to the backend.
  Future<void> _saveNew() async {
    final FormState form = _newFormKey.currentState!;
    if (!form.validate()) return;

    final Map<String, dynamic> body = <String, dynamic>{
      'site_id': widget.site['id'],
      'stream_name': _newNameCtl.text.trim(),
      'video_url': _newUrlCtl.text.trim(),
      'model_key': _newModelKey,
      'recognition_enabled': _newRecognitionEnabled,
      'work_start_hour': _newStartHour,
      'work_end_hour': _newEndHour,
      if (_newExpireDate != null)
        'expire_date': _newExpireDate!.toIso8601String(),
      ..._newDetect,
    };

    form.reset();
    _newDetect.updateAll((_, __) => false);
    _newRecognitionEnabled = true;
    _newStartHour = 7;
    _newEndHour = 18;
    _newExpireDate = null;

    try {
      await AuthUtils.withAuthRetryOnError(
        context,
        (String tk) =>
            ManagementAPIService.createStreamConfig(body: body, token: tk),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.streamAdded)));
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('❌ $e')));
    }
  }

  /// Builds the section for adding a new stream config.
  Widget _buildAddSection() {
    final int? maxStreams = _maxStreams;
    if (maxStreams != null && _usedStreams >= maxStreams) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
            AppLocalizations.of(context)!.streamLimitReached(maxStreams),
            style: TextStyle(color: Theme.of(context).colorScheme.tertiary)),
      );
    }

    return Form(
      key: _newFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(AppLocalizations.of(context)!.addStream,
              style: Theme.of(context).textTheme.titleMedium),
          TextFormField(
            controller: _newNameCtl,
            decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.streamName),
            validator: (String? v) => v == null || v.trim().isEmpty
                ? AppLocalizations.of(context)!.required
                : null,
          ),
          TextFormField(
            controller: _newUrlCtl,
            decoration: const InputDecoration(labelText: 'RTSP / HTTP URL'),
            validator: (String? v) => v == null || v.trim().isEmpty
                ? AppLocalizations.of(context)!.required
                : null,
          ),
          DropdownButtonFormField<String>(
            initialValue: _newModelKey,
            decoration: const InputDecoration(labelText: 'Model key'),
            items: _modelOptions
                .map((String e) => DropdownMenuItem<String>(
                    value: e, child: Text(e.toUpperCase())))
                .toList(),
            onChanged: (String? v) =>
                setState(() => _newModelKey = v ?? 'yolo26n'),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _newStartHour,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.startHour),
                  items: _hourOptions
                      .map((int h) => DropdownMenuItem<int>(
                          value: h, child: Text(h.toString())))
                      .toList(),
                  onChanged: (int? v) =>
                      setState(() => _newStartHour = v ?? _newStartHour),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _newEndHour,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.endHour),
                  items: _hourOptions
                      .map((int h) => DropdownMenuItem<int>(
                          value: h, child: Text(h.toString())))
                      .toList(),
                  onChanged: (int? v) =>
                      setState(() => _newEndHour = v ?? _newEndHour),
                ),
              ),
            ],
          ),
          SwitchListTile(
            dense: true,
            title: Text(AppLocalizations.of(context)!.recognitionEnabled),
            subtitle:
                Text(AppLocalizations.of(context)!.recognitionEnabledHint),
            value: _newRecognitionEnabled,
            onChanged: (bool v) => setState(() => _newRecognitionEnabled = v),
          ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(AppLocalizations.of(context)!.expiryDate),
            subtitle: Text(_newExpireDate == null
                ? AppLocalizations.of(context)!.notSet
                : DateFormat('yyyy/MM/dd').format(_newExpireDate!)),
            trailing: IconButton(
              icon: const Icon(Icons.date_range),
              onPressed: () => _pickDate(
                current: _newExpireDate,
                onPicked: (DateTime? d) => setState(() => _newExpireDate = d),
                ctx: context,
              ),
            ),
          ),
          _buildToggleGroup(context, _newDetect, setState),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _saveNew,
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.of(context)!.add),
            ),
          ),
        ],
      ),
    );
  }

  /// Edits an existing stream config [cfg].
  Future<void> _editConfig(Map cfg) async {
    final TextEditingController nameCtl =
        TextEditingController(text: cfg['stream_name'] as String?);
    final TextEditingController urlCtl =
        TextEditingController(text: cfg['video_url'] as String?);
    String selModel = (cfg['model_key'] as String?) ?? 'yolo26n';
    final Map<String, bool> det = <String, bool>{
      'detect_no_safety_vest_or_helmet':
          (cfg['detect_no_safety_vest_or_helmet'] as bool? ?? false),
      'detect_near_machinery_or_vehicle':
          (cfg['detect_near_machinery_or_vehicle'] as bool? ?? false),
      'detect_in_restricted_area':
          (cfg['detect_in_restricted_area'] as bool? ?? false),
      'detect_in_utility_pole_restricted_area':
          (cfg['detect_in_utility_pole_restricted_area'] as bool? ?? false),
      'detect_machinery_close_to_pole':
          (cfg['detect_machinery_close_to_pole'] as bool? ?? false),
    };
    // Missing from an older API response means the existing stream should
    // retain the historic behaviour of running recognition.
    bool recognitionEnabled = cfg['recognition_enabled'] as bool? ?? true;
    int startHour = cfg['work_start_hour'] as int? ?? 7;
    int endHour = cfg['work_end_hour'] as int? ?? 18;
    DateTime? expireDt = cfg['expire_date'] != null
        ? DateTime.tryParse(cfg['expire_date'] as String)
        : null;
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogCtx) => AlertDialog(
        title:
            Text(AppLocalizations.of(context)!.editStream(cfg['stream_name'])),
        content: StatefulBuilder(builder:
            (BuildContext sbCtx, void Function(void Function()) setDlg) {
          return SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextFormField(
                      controller: nameCtl,
                      decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!.streamName),
                      validator: (String? v) => v == null || v.trim().isEmpty
                          ? AppLocalizations.of(context)!.required
                          : null,
                    ),
                    TextFormField(
                      controller: urlCtl,
                      decoration:
                          const InputDecoration(labelText: 'RTSP / HTTP URL'),
                      validator: (String? v) => v == null || v.trim().isEmpty
                          ? AppLocalizations.of(context)!.required
                          : null,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: selModel,
                      decoration: const InputDecoration(labelText: 'Model key'),
                      items: _modelOptions
                          .map((String e) => DropdownMenuItem<String>(
                              value: e, child: Text(e.toUpperCase())))
                          .toList(),
                      onChanged: (String? v) =>
                          setDlg(() => selModel = v ?? selModel),
                    ),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: startHour,
                            decoration: InputDecoration(
                                labelText:
                                    AppLocalizations.of(context)!.startHour),
                            items: _hourOptions
                                .map((int h) => DropdownMenuItem<int>(
                                    value: h, child: Text(h.toString())))
                                .toList(),
                            onChanged: (int? v) =>
                                setDlg(() => startHour = v ?? startHour),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: endHour,
                            decoration: InputDecoration(
                                labelText:
                                    AppLocalizations.of(context)!.endHour),
                            items: _hourOptions
                                .map((int h) => DropdownMenuItem<int>(
                                    value: h, child: Text(h.toString())))
                                .toList(),
                            onChanged: (int? v) =>
                                setDlg(() => endHour = v ?? endHour),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      dense: true,
                      title: Text(
                          AppLocalizations.of(context)!.recognitionEnabled),
                      subtitle: Text(
                          AppLocalizations.of(context)!.recognitionEnabledHint),
                      value: recognitionEnabled,
                      onChanged: (bool v) =>
                          setDlg(() => recognitionEnabled = v),
                    ),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(AppLocalizations.of(context)!.expiryDate),
                      subtitle: Text(expireDt == null
                          ? AppLocalizations.of(context)!.notSet
                          : DateFormat('yyyy/MM/dd').format(expireDt!)),
                      trailing: IconButton(
                        icon: const Icon(Icons.date_range),
                        onPressed: () => _pickDate(
                          current: expireDt,
                          onPicked: (DateTime? d) => setDlg(() => expireDt = d),
                          ctx: dialogCtx,
                        ),
                      ),
                    ),
                    const Divider(),
                    _buildToggleGroup(sbCtx, det, setDlg),
                  ],
                ),
              ),
            ),
          );
        }),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(AppLocalizations.of(context)!.cancel)),
          ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: Text(AppLocalizations.of(context)!.save)),
        ],
      ),
    );

    if (ok != true) return;
    if (!formKey.currentState!.validate()) return;

    if (!mounted) return;

    final Map<String, dynamic> body = <String, dynamic>{
      'stream_name': nameCtl.text.trim(),
      'video_url': urlCtl.text.trim(),
      'model_key': selModel,
      'recognition_enabled': recognitionEnabled,
      'work_start_hour': startHour,
      'work_end_hour': endHour,
      if (expireDt != null) 'expire_date': expireDt?.toIso8601String(),
      ...det,
    };

    try {
      await AuthUtils.withAuthRetryOnError(
          context,
          (String tk) => ManagementAPIService.updateStreamConfig(
                cfgId: cfg['id'] as int,
                body: body,
                token: tk,
              ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.updated)));
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('❌ $e')));
    }
  }

  /// Deletes a stream config by [id].
  Future<void> _deleteConfig(int id) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext _) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.deleteStream),
        content: Text(AppLocalizations.of(context)!.deleteStreamConfirmation),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context)!.cancel)),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context)!.delete)),
        ],
      ),
    );
    if (ok != true) return;

    if (!mounted) return;

    try {
      await AuthUtils.withAuthRetryOnError(
          context,
          (String tk) =>
              ManagementAPIService.deleteStreamConfig(cfgId: id, token: tk));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.deleted)));
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('❌ $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  /// Reloads the stream config data from the backend.
  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final int sId = widget.site['id'] as int;

      final List<dynamic> configs = await AuthUtils.withAuthRetryOnError(
          context,
          (String tk) => ManagementAPIService.listStreamConfigsOfSite(
                siteId: sId,
                token: tk,
              ));
      if (!mounted) return;
      _currentConfigs = configs;
      _usedStreams = _currentConfigs.length;
      _maxStreams = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Builds the list of current stream configs.
  Widget _buildList() {
    if (_currentConfigs.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context)!.noStreamConfig));
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      itemCount: _currentConfigs.length,
      separatorBuilder: (BuildContext _, int __) => const Divider(height: 1),
      itemBuilder: (BuildContext _, int i) {
        final ColorScheme colors = Theme.of(context).colorScheme;
        final dynamic c = _currentConfigs[i];
        return ListTile(
          title: Text(c['stream_name'] as String),
          subtitle: Text(c['video_url'] as String),
          trailing: Wrap(
            spacing: 4,
            children: <Widget>[
              IconButton(
                icon: Icon(Icons.edit, color: colors.primary),
                tooltip: AppLocalizations.of(context)!.edit,
                onPressed: () => _editConfig(c as Map),
              ),
              IconButton(
                icon: Icon(Icons.delete, color: colors.error),
                tooltip: AppLocalizations.of(context)!.delete,
                onPressed: () => _deleteConfig(c['id'] as int),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
          AppLocalizations.of(context)!.streamConfigTitle(widget.site['name'])),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Text(_error!)
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (_maxStreams != null) ...<Widget>[
                          Text(
                              AppLocalizations.of(context)!
                                  .streamUsage(_usedStreams, _maxStreams!),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                        ],
                        _buildList(),
                        const Divider(height: 24),
                        _buildAddSection(),
                      ],
                    ),
                  ),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context)!.close)),
      ],
    );
  }
}
