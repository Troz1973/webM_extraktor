#!/bin/bash

# ================================================
# FFmpeg WebM Last Frame Extractor
# Extrahuje poslední frame z WebM videí s alfou
# a volitelně aplikuje průhlednost
# ================================================

# Konfigurace
INPUT_DIR="./input"
OUTPUT_DIR="./output"
TEMP_DIR="./temp"
APPLY_ALPHA="${APPLY_ALPHA:-false}"   # true/false - zapnout/vypnout změnu alphy
ALPHA="${ALPHA:-0.3}"                # Průhlednost (0.0-1.0) - platí jen když APPLY_ALPHA=true
CRF=15                       # Kvalita (0-63, nižší = lepší)
INPUT_CODEC="libvpx-vp9"     # Vstupní kodek
OUTPUT_CODEC="libvpx-vp9"    # Výstupní kodek

# Barvy pro výstup
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Vytvoř složky
mkdir -p "$OUTPUT_DIR"
mkdir -p "$TEMP_DIR"

# Počítadlo
count=0
success=0
failed=0
total=$(find "$INPUT_DIR" -maxdepth 1 -name "*.webm" -type f 2>/dev/null | wc -l)

# Header
echo "================================================"
echo "  FFmpeg WebM Last Frame Extractor"
echo "================================================"
echo "Vstupní kodek:  $INPUT_CODEC"
echo "Výstupní kodek: $OUTPUT_CODEC"
echo "Vstup:          $INPUT_DIR"
echo "Výstup:         $OUTPUT_DIR"

if [ "$APPLY_ALPHA" = true ]; then
    alpha_percent=$(echo "$ALPHA * 100" | bc | cut -d. -f1)
    echo -e "Změna alphy:    ${GREEN}ZAPNUTA${NC} ($ALPHA = ${alpha_percent}%)"
else
    echo -e "Změna alphy:    ${YELLOW}VYPNUTA${NC} (zachovat originál)"
fi

echo "CRF kvalita:    $CRF"
echo "================================================"
echo ""

# Kontrola vstupní složky
if [ ! -d "$INPUT_DIR" ]; then
    echo -e "${RED}❌ Vstupní složka neexistuje: $INPUT_DIR${NC}"
    exit 1
fi

# Kontrola souborů
if [ $total -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Žádné WebM soubory nenalezeny v $INPUT_DIR${NC}"
    exit 1
fi

echo -e "${BLUE}Nalezeno $total WebM souborů...${NC}"
echo ""

# Začátek měření času
start_time=$(date +%s)

# Hlavní smyčka
for f in "$INPUT_DIR"/*.webm; do
    # Kontrola existence souboru
    [ -f "$f" ] || continue
    
    filename=$(basename "$f")
    name="${filename%.webm}"
    
    # === PŘEJMENOVÁNÍ: Odstraň čísla na konci a přidej "_1" ===
    if [[ "$name" =~ ^(.+)_[0-9]+$ ]]; then
        name_without_number="${BASH_REMATCH[1]}"
    else
        name_without_number="$name"
    fi
    output_name="${name_without_number}_1"
    
    temp_png="$TEMP_DIR/${name}_temp.png"
    output="$OUTPUT_DIR/${output_name}.webm"
    
    count=$((count + 1))
    
    echo -e "${BLUE}[$count/$total]${NC} 🎬 $filename"
    echo -e "   ${CYAN}→ Výstup: ${output_name}.webm${NC}"
    
    # ===== KROK 1: Extrakce posledního framu jako PNG =====
    echo "   → Extrahuji poslední frame..."
    
    if ffmpeg -y \
        -c:v "$INPUT_CODEC" \
        -sseof -0.04 \
        -i "$f" \
        -vframes 1 \
        -pix_fmt rgba \
        -loglevel error \
        "$temp_png" 2>&1; then
        
        png_size=$(du -h "$temp_png" | cut -f1)
        echo "   → PNG extrahováno ($png_size)"
    else
        echo -e "   ${RED}❌ Chyba při extrakci PNG${NC}"
        failed=$((failed + 1))
        rm -f "$temp_png"
        echo ""
        continue
    fi
    
    # ===== KROK 2: Konverze na WebM (s nebo bez změny alphy) =====
    
    # Sestavení video filtru
    if [ "$APPLY_ALPHA" = true ]; then
        vf_filter="colorchannelmixer=aa=$ALPHA"
        echo "   → Aplikuji průhlednost ($ALPHA) a převádím na WebM..."
    else
        vf_filter=""
        echo "   → Převádím na WebM (bez změny alphy)..."
    fi
    
    # FFmpeg příkaz s podmíněným filtrem
    if [ -n "$vf_filter" ]; then
        ffmpeg_cmd=(ffmpeg -y -i "$temp_png" -vf "$vf_filter" -c:v "$OUTPUT_CODEC" -pix_fmt yuva420p -b:v 0 -crf $CRF -loglevel error -stats "$output")
    else
        ffmpeg_cmd=(ffmpeg -y -i "$temp_png" -c:v "$OUTPUT_CODEC" -pix_fmt yuva420p -b:v 0 -crf $CRF -loglevel error -stats "$output")
    fi
    
    if "${ffmpeg_cmd[@]}" 2>&1; then
        
        output_size=$(du -h "$output" | cut -f1)
        success=$((success + 1))
        echo -e "   ${GREEN}✅ $output_size → ${output_name}.webm${NC}"
        
        # Ověření alfa kanálu
        has_alpha=$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=noprint_wrappers=1:nokey=1 "$output" 2>&1 | grep -c "yuva")
        if [ "$has_alpha" -eq 1 ]; then
            echo -e "   ${GREEN}✓${NC} Alfa kanál zachován"
        else
            echo -e "   ${YELLOW}⚠${NC} Varování: Alfa kanál možná chybí"
        fi
    else
        echo -e "   ${RED}❌ Chyba při konverzi na WebM${NC}"
        failed=$((failed + 1))
    fi
    
    # Smaž dočasný PNG
    rm -f "$temp_png"
    echo ""
done

# Vyčisti temp složku
rmdir "$TEMP_DIR" 2>/dev/null

# Konec měření času
end_time=$(date +%s)
duration=$((end_time - start_time))

# Footer
echo "================================================"
echo "  🎉 Zpracování dokončeno!"
echo "================================================"
echo "Celkem souborů:  $total"
echo -e "${GREEN}Úspěšně:${NC}         $success"
if [ $failed -gt 0 ]; then
    echo -e "${RED}Selhalo:${NC}          $failed"
fi
echo "Čas:             ${duration}s"
echo "Výstup:          $OUTPUT_DIR"
echo "================================================"

# Exit code podle výsledku
if [ $failed -gt 0 ]; then
    exit 1
else
    exit 0
fi