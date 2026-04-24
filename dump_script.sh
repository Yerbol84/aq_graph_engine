#!/bin/bash
# improved_dump_with_skipped.sh – дамп Flutter-проекта с отчётом о пропущенных файлах
# Теперь можно указать, какие корневые папки включать (по умолчанию только lib/)

set -euo pipefail

# ---------- НАСТРОЙКИ ----------
MAX_LINES_PER_FILE=5000
MAX_TOTAL_SIZE_MB=10               # 0 = без лимита

# Какие папки в КОРНЕ проекта включать (рекурсивно)
INCLUDE_ROOT_DIRS=("lib" 
# "pkgs" 
"doc" 
# "server_apps" 
"deploys"
)

# Какие отдельные файлы в КОРНЕ включать (например, конфиги)
INCLUDE_ROOT_FILES=("pubspec.yaml" "README.md" "analysis_options.yaml" ".gitignore"
  "doc/AQ_ARCHITECTURE_RULES.md"
  "doc/project_consts_rules.md"
  "doc/MCP_protocol_rules.md" "GRAPH_ENGINE_GUIDE.md"
)

# Директории, которые исключаются В ЛЮБОМ МЕСТЕ (кроме тех, что входят в INCLUDE_ROOT_DIRS)
EXCLUDE_DIRS=(".dart_tool" ".git" "ios/Pods" "macos/Pods" "android/.gradle" "build" "ios" "android" ".idea" "linux" "macos" "windows" "web" "test" "doc/todo" "doc/tender") 

# Расширения, которые гарантированно не нужны (дополнительная фильтрация)
BINARY_EXTENSIONS=("png" "jpg" "jpeg" "gif" "bmp" "ico" "mp3" "mp4" "avi" "mov" "pdf" "doc" "docx" "zip" "tar" "gz" "rar" "7z" "class" "o" "so" "dll" "exe" "pyc" "pyo")
# ---------------------------------


EXCLUDE_PATTERNS=(
  "*.g.dart" "*.freezed.dart" "*.pbxproj" "*.xcconfig" "*.plist"
  "*.iml" "*.lock" "*.html" "*.css" "*.js" "README.md" "CHANGELOG.md"
)

# Проверка наличия file
if ! command -v file &> /dev/null; then
    echo "Предупреждение: команда 'file' не найдена, буду использовать упрощённую проверку бинарных файлов." >&2
    USE_FILE=false
else
    USE_FILE=true
fi

# Получить имя проекта
PROJECT_NAME=$(grep '^name:' pubspec.yaml 2>/dev/null | head -n1 | awk '{print $2}') || true
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME=$(basename "$PWD")
    echo "Предупреждение: имя проекта не найдено в pubspec.yaml, использую имя папки: $PROJECT_NAME" >&2
fi

OUT="${PROJECT_NAME}_dump.md"
> "$OUT"

# Функция проверки, нужно ли исключить директорию (по полному пути)
is_excluded_dir() {
    local path="$1"
    # Нормализуем путь: убираем ведущий ./
    path="${path#./}"

    # Проверяем, не входит ли путь в одну из исключаемых поддиректорий
    for excl in "${EXCLUDE_DIRS[@]}"; do
        if [[ "$path" == "$excl" || "$path" == "$excl"/* || "$path" == */"$excl" || "$path" == */"$excl"/* ]]; then
            return 0
        fi
    done
    return 1
}

# Функция проверки, является ли файл текстовым
is_text_file() {
    local file="$1"
    if $USE_FILE; then
        if file -b --mime-type "$file" | grep -q '^text/'; then
            return 0
        else
            return 1
        fi
    else
        # Fallback: ищем нулевой байт
        if head -c 1024 "$file" | grep -q -F -m 1 ''; then
            return 1
        else
            return 0
        fi
    fi
}

# Сбор файлов (только из разрешённых корневых папок и отдельных файлов)
all_files=()

# 1. Добавляем файлы из разрешённых корневых папок
for dir in "${INCLUDE_ROOT_DIRS[@]}"; do
    if [ -d "./$dir" ]; then
        while IFS= read -r -d '' file; do
            all_files+=("$file")
        done < <(find "./$dir" -type f -print0 2>/dev/null || true)
    fi
done

# 2. Добавляем отдельные файлы из корня
for fname in "${INCLUDE_ROOT_FILES[@]}"; do
    if [ -f "./$fname" ]; then
        all_files+=("./$fname")
    fi
done

# Убираем дубликаты (на случай, если файл попал дважды – маловероятно)
all_files=($(printf "%s\n" "${all_files[@]}" | sort -u))

# Массивы для включённых и пропущенных
included_files=()
skipped_files=()  # каждый элемент = "путь|причина"
skipped_files+=("1|1")
total_size=0
total_lines=0

# Функция добавления файла в дамп
process_file() {
    local file="$1"
    local reason=""
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        if [[ "$file" == $pattern ]]; then
            skipped_files+=("$file|исключён по шаблону")
            return
        fi
    done
    # 1. Проверка на исключённую директорию
    if is_excluded_dir "$file"; then
        skipped_files+=("$file|исключённая директория")
        return
    fi

    # 2. Проверка на текстовость
    if ! is_text_file "$file"; then
        skipped_files+=("$file|бинарный файл")
        return
    fi

    # 3. Дополнительная фильтрация по расширению
    ext="${file##*.}"
    for bext in "${BINARY_EXTENSIONS[@]}"; do
        if [[ "$ext" == "$bext" ]]; then
            skipped_files+=("$file|бинарное расширение")
            return
        fi
    done

    # Если дошли сюда – файл подходит
    lines=$(wc -l < "$file" 2>/dev/null || echo "0")
    size=$(wc -c < "$file" 2>/dev/null || echo "0")

    # Проверка общего лимита
    if [ "$MAX_TOTAL_SIZE_MB" -gt 0 ]; then
        new_total=$((total_size + size))
        new_total_mb=$((new_total / 1048576))
        if [ "$new_total_mb" -gt "$MAX_TOTAL_SIZE_MB" ]; then
            skipped_files+=("$file|превышен общий лимит размера дампа")
            return
        fi
    fi

    included_files+=("$file|$lines|$size")
    total_size=$((total_size + size))
    total_lines=$((total_lines + lines))
}

# Обрабатываем все собранные файлы
for file in "${all_files[@]}"; do
    process_file "$file"
done

# Сортировка
IFS=$'\n' sorted_included=($(sort <<<"${included_files[*]}"))
IFS=$'\n' sorted_skipped=($(sort <<<"${skipped_files[*]}"))
unset IFS

# --- Запись дампа ---
{
    echo "# Дамп проекта $PROJECT_NAME"
    echo ""
    echo "**Всего обработано файлов:** ${#all_files[@]}"
    echo "**Включено:** ${#included_files[@]}"
    echo "**Пропущено:** ${#skipped_files[@]}"
    echo ""
    echo "## Включённые файлы"
    echo ""
    echo "| Файл | Строк | Размер (байт) |"
    echo "|------|-------|---------------|"
    for entry in "${sorted_included[@]}"; do
        IFS='|' read -r path lines size <<< "$entry"
        echo "| \`$path\` | $lines | $size |"
    done
    echo ""
    echo "---"
    echo ""
    echo "## Пропущенные файлы"
    echo ""
    echo "| Файл | Причина |"
    echo "|------|---------|"
    for entry in "${sorted_skipped[@]}"; do
        IFS='|' read -r path reason <<< "$entry"
        echo "| \`$path\` | $reason |"
    done
    echo ""
    echo "---"
    echo ""
    echo "## Содержимое включённых файлов"
    echo ""

    # Выводим содержимое
    for entry in "${sorted_included[@]}"; do
        IFS='|' read -r path lines size <<< "$entry"
        # Определяем язык для подсветки
        case "${path##*.}" in
            dart) lang="dart" ;;
            yaml|yml) lang="yaml" ;;
            json) lang="json" ;;
            md)   lang="markdown" ;;
            lock) lang="yaml" ;;
            gradle) lang="groovy" ;;
            plist) lang="xml" ;;
            pbxproj) lang="javascript" ;;
            sh)   lang="bash" ;;
            *)    lang="" ;;
        esac

        echo "### Файл: \`$path\` (строк: $lines, размер: $size байт)"
        echo ""
        if [ -n "$lang" ]; then
            echo "\`\`\`$lang"
        else
            echo "\`\`\`"
        fi

        if [ "$lines" -le "$MAX_LINES_PER_FILE" ]; then
            cat "$path" 2>/dev/null || echo "<!-- Ошибка чтения файла -->"
        else
            head -n "$MAX_LINES_PER_FILE" "$path" 2>/dev/null || echo "<!-- Ошибка чтения файла -->"
            echo ""
            echo "# --- Обрезано после $MAX_LINES_PER_FILE строк ---"
        fi
        echo "\`\`\`"
        echo ""
    done

    # Финальная статистика
    echo "---"
    echo "**Суммарно строк в включённых файлах:** $total_lines"
    echo "**Суммарный размер включённых файлов:** $total_size байт (~$((total_size / 1024)) КБ)"
} >> "$OUT"

echo "Готово! Дамп сохранён в $OUT"
echo "Включено файлов: ${#included_files[@]}, пропущено: ${#skipped_files[@]}"