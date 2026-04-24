// Базовый интерфейс для всех узлов Workflow графа
// Заменяет enum-based подход на полиморфную иерархию

import 'package:aq_schema/aq_schema.dart';
import '../../interfaces/i_graph_repository.dart';

/// Базовый интерфейс для всех узлов Workflow графа
///
/// Все конкретные узлы (LlmActionNode, FileReadNode, etc.) реализуют этот интерфейс.
/// Это позволяет:
/// - Типобезопасность (вместо Map<String, dynamic> config)
/// - Расширяемость (добавить новый узел без изменения WorkflowRunner)
/// - Полиморфизм (await node.execute() вместо гигантского switch)
abstract class IWorkflowNode extends $Node {
  @override
  String get id;

  /// Тип узла для сериализации (llmAction, fileRead, etc.)
  /// Используется при сохранении в JSON
  String get nodeType;

  /// Выполнить узел
  ///
  /// [context] - контекст выполнения с переменными
  /// [tools] - реестр IHand для выполнения действий
  /// [graphRepo] - репозиторий для загрузки вложенных графов
  ///
  /// Возвращает результат выполнения (может быть null)
  Future<dynamic> execute(
    RunContext context,
    ToolRegistry tools,
    IGraphRepository graphRepo,
  );

  /// Сериализация в JSON
  /// Формат: { "id": "...", "type": "...", "config": {...} }
  Map<String, dynamic> toJson();

  @override
  IWorkflowNode copyWith();
}
