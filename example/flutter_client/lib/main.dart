// pkgs/aq_graph_engine/example/flutter_client/lib/main.dart
//
// Пример Flutter приложения которое запускает граф через HTTP.
//
// ── Как работает ─────────────────────────────────────────────────────────────
//
// 1. Инициализируем IGraphEngineClient с URL воркера
// 2. Нажимаем "Run Graph" — отправляем GraphRunRequest
// 3. Получаем события через SSE stream и показываем в UI
// 4. При userInputRequired — показываем диалог ввода
//
// ── Запуск ───────────────────────────────────────────────────────────────────
//
// 1. Запустить воркер:
//    cd server_apps/aq_graph_worker && dart run bin/main.dart
//
// 2. Запустить Flutter:
//    cd pkgs/aq_graph_engine/example/flutter_client
//    flutter run

import 'package:flutter/material.dart';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import 'package:uuid/uuid.dart';

void main() {
  // Инициализируем клиент движка — единственная строка конфигурации
  IGraphEngineClient.init(HttpGraphEngineClient(
    baseUrl: 'http://localhost:8092',
  ));

  runApp(const GraphEngineExampleApp());
}

class GraphEngineExampleApp extends StatelessWidget {
  const GraphEngineExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AQ Graph Engine',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const GraphRunScreen(),
    );
  }
}

// ── Экран запуска графа ───────────────────────────────────────────────────────

class GraphRunScreen extends StatefulWidget {
  const GraphRunScreen({super.key});

  @override
  State<GraphRunScreen> createState() => _GraphRunScreenState();
}

class _GraphRunScreenState extends State<GraphRunScreen> {
  final _blueprintIdController = TextEditingController(
    text: 'my-workflow-id',
  );
  final _projectIdController = TextEditingController(
    text: 'project-1',
  );

  final List<_LogEntry> _logs = [];
  String _status = 'idle';
  String? _currentRunId;
  bool _isRunning = false;
  bool _workerAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkWorker();
  }

  Future<void> _checkWorker() async {
    final available = await IGraphEngineClient.instance.isAvailable();
    setState(() => _workerAvailable = available);
  }

  Future<void> _startRun() async {
    if (_isRunning) return;

    final runId = const Uuid().v4();
    _currentRunId = runId;

    setState(() {
      _logs.clear();
      _status = 'starting';
      _isRunning = true;
    });

    _addLog('🚀 Starting run: ${runId.substring(0, 8)}...', 'system');

    final request = GraphRunRequest(
      runId: runId,
      blueprintId: _blueprintIdController.text.trim(),
      projectId: _projectIdController.text.trim(),
      projectPath: '/projects/${_projectIdController.text.trim()}',
    );

    try {
      final stream = IGraphEngineClient.instance.run(request);

      await for (final event in stream) {
        _handleEvent(event);

        // Завершаем при финальных событиях
        if (event.type == GraphRunEventType.completed ||
            event.type == GraphRunEventType.error) {
          break;
        }
      }
    } catch (e) {
      _addLog('❌ Error: $e', 'error');
      setState(() => _status = 'error');
    } finally {
      setState(() => _isRunning = false);
    }
  }

  void _handleEvent(GraphRunEvent event) {
    switch (event.type) {
      case GraphRunEventType.log:
        _addLog(event.message ?? '', event.logType ?? 'info');

      case GraphRunEventType.statusChanged:
        final status = event.newStatus?.name ?? 'unknown';
        setState(() => _status = status);
        _addLog('📊 Status: $status', 'system');

      case GraphRunEventType.completed:
        setState(() => _status = 'completed');
        _addLog('✅ Completed!', 'system');

      case GraphRunEventType.error:
        setState(() => _status = 'error');
        _addLog('❌ ${event.errorMessage ?? event.message ?? "Error"}', 'error');

      case GraphRunEventType.userInputRequired:
        setState(() => _status = 'suspended');
        _addLog('⏸️ Waiting for input...', 'system');
        _showInputDialog(event.inputRequiredPayload ?? {});

      default:
        break;
    }
  }

  void _addLog(String message, String type) {
    setState(() {
      _logs.add(_LogEntry(
        message: message,
        type: type,
        time: DateTime.now(),
      ));
    });
  }

  Future<void> _showInputDialog(Map<String, dynamic> payload) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Input Required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (payload['prompt'] != null)
              Text(payload['prompt'] as String),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Enter your response...',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (result != null && _currentRunId != null) {
      await IGraphEngineClient.instance.resume(UserInputResponse(
        runId: _currentRunId!,
        values: {'user_input': result},
      ));
      _addLog('▶️ Resumed with input', 'system');
    }
  }

  Future<void> _cancelRun() async {
    if (_currentRunId == null) return;
    await IGraphEngineClient.instance.cancel(_currentRunId!);
    setState(() {
      _status = 'cancelled';
      _isRunning = false;
    });
    _addLog('🛑 Cancelled', 'system');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AQ Graph Engine'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Индикатор доступности воркера
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 12,
                  color: _workerAvailable ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 6),
                Text(
                  _workerAvailable ? 'Worker online' : 'Worker offline',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: _checkWorker,
                  tooltip: 'Check worker',
                ),
              ],
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Конфигурация ──────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Run Configuration',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _blueprintIdController,
                      decoration: const InputDecoration(
                        labelText: 'Blueprint ID',
                        hintText: 'workflow graph ID',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _projectIdController,
                      decoration: const InputDecoration(
                        labelText: 'Project ID',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Кнопки управления ─────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isRunning || !_workerAvailable ? null : _startRun,
                    icon: _isRunning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(_isRunning ? 'Running...' : 'Run Graph'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _isRunning ? _cancelRun : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Cancel'),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // ── Статус ────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _statusColor(_status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _statusColor(_status).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    _statusIcon(_status),
                    size: 16,
                    color: _statusColor(_status),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Status: $_status',
                    style: TextStyle(
                      color: _statusColor(_status),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_currentRunId != null) ...[
                    const Spacer(),
                    Text(
                      'Run: ${_currentRunId!.substring(0, 8)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Лог событий ───────────────────────────────────────────────
            Expanded(
              child: Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Text(
                            'Events',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const Spacer(),
                          if (_logs.isNotEmpty)
                            TextButton(
                              onPressed: () => setState(() => _logs.clear()),
                              child: const Text('Clear'),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _logs.isEmpty
                          ? const Center(
                              child: Text(
                                'No events yet.\nPress "Run Graph" to start.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: _logs.length,
                              itemBuilder: (ctx, i) {
                                final log = _logs[i];
                                return _LogEntryWidget(entry: log);
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'running':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'error':
        return Colors.red;
      case 'suspended':
        return Colors.orange;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'running':
        return Icons.play_circle;
      case 'completed':
        return Icons.check_circle;
      case 'error':
        return Icons.error;
      case 'suspended':
        return Icons.pause_circle;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.circle_outlined;
    }
  }

  @override
  void dispose() {
    _blueprintIdController.dispose();
    _projectIdController.dispose();
    IGraphEngineClient.instance.dispose();
    super.dispose();
  }
}

// ── Log Entry ─────────────────────────────────────────────────────────────────

class _LogEntry {
  final String message;
  final String type;
  final DateTime time;

  _LogEntry({
    required this.message,
    required this.type,
    required this.time,
  });
}

class _LogEntryWidget extends StatelessWidget {
  final _LogEntry entry;

  const _LogEntryWidget({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.type) {
      'error' => Colors.red,
      'system' => Colors.blue,
      'warning' => Colors.orange,
      _ => Colors.black87,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${entry.time.hour.toString().padLeft(2, '0')}:'
            '${entry.time.minute.toString().padLeft(2, '0')}:'
            '${entry.time.second.toString().padLeft(2, '0')}',
            style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
