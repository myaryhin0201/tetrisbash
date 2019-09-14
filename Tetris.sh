set -u # niezainicjowana zmienna jest błędem

# Używane są 2 sygnały: SIGUSR1, aby zmienić opóźnienie po podniesieniu poziomu i SIGUSR2, aby wyjść
# są wysyłane do wszystkich instancji tego skryptu
# z tego powodu powinniśmy je przetwarzać w każdym przypadku
# w tym przypadku ignorujemy oba sygnał
trap '' SIGUSR1 SIGUSR2

# Są to polecenia wysyłane do kontrolera za pomocą kodu przetwarzania klucza
# W kontrolerze są używane jako indeks do pobierania rzeczywistego funktuonu z tablicy
QUIT=0
RIGHT=1
LEFT=2
ROTATE=3
DOWN=4
DROP=5
DELAY=1000          # początkowe opóźnienie między ruchami części (milisekundy)
DELAY_FACTOR="8/10" # ta wartość kontroluje zmniejszenie opóźnienia dla każdego poziomu w górę

# kolory
RED=1
GREEN=2
YELLOW=3
BLUE=4
FUCHSIA=5
CYAN=6
WHITE=7

# Lokalizacja i rozmiar pola gry, kolor granicy
PLAYFIELD_W=10
PLAYFIELD_H=20
PLAYFIELD_X=30
PLAYFIELD_Y=1
BORDER_COLOR=$GREEN

# Lokalizacja i kolor informacji o wyniku
SCORE_X=1
SCORE_Y=2
SCORE_COLOR=$YELLOW

# Lokalizacja i kolor informacji pomocy
HELP_X=58
HELP_Y=1
HELP_COLOR=$WHITE

# Lokalizacja następnego kawałka
NEXT_X=14
NEXT_Y=11

# Lokalizacja „zakończenia gry” na końcu gry
GAMEOVER_X=1
GAMEOVER_Y=$((PLAYFIELD_H + 3))

# Interwały, po których zwiększa się poziom gry (i szybkość gry)
LEVEL_UP=20

colors=($RED $GREEN $YELLOW $BLUE $FUCHSIA $CYAN $WHITE)

use_color=1      
showtime=1       
empty_cell=" ."   
filled_cell="[]" 

score=0           # inicjalizacja zmiennej wynikowej
level=1           # inicjalizacja zmiennej poziomu
lines_completed=0 # zakończone inicjowanie licznika linii


# screen_buffer jest zmienną, która gromadzi wszystkie zmiany na ekranie
# ta zmienna jest drukowana w kontrolerze raz na cykl gry
puts() {
    screen_buffer+=${1}
}

# przenieś kursor na (x, y) i ciąg wydruku
# (1,1) to lewy górny róg ekranu
xyprint() {
    puts "\033[${2};${1}H${3}"
}

show_cursor() {
    echo -ne "\033[?25h"
}

hide_cursor() {
    echo -ne "\033[?25l"
}

# kolor pierwszego planu
set_fg() {
    ((use_color)) && puts "\033[3${1}m"
}

# kolor tła
set_bg() {
    ((use_color)) && puts "\033[4${1}m"
}

reset_colors() {
    puts "\033[0m"
}

set_bold() {
    puts "\033[1m"
}

# playfield jest tablicą, każdy wiersz jest reprezentowany przez liczbę całkowitą
# każda komórka zajmuje 3 bity (puste, jeśli 0, inne wartości kodują kolor)
redraw_playfield() {
    local x y color

    for ((y = 0; y < PLAYFIELD_H; y++)) {
        xyprint $PLAYFIELD_X $((PLAYFIELD_Y + y)) ""
        for ((x = 0; x < PLAYFIELD_W; x++)) {
            ((color = ((playfield[y] >> (x * 3)) & 7)))
            if ((color == 0)) ; then
                puts "$empty_cell"
            else
                set_fg $color
                set_bg $color
                puts "$filled_cell"
                reset_colors
            fi
        }
    }
}

update_score() {
    # Argumenty: 1 - liczba ukończonych linii
    ((lines_completed += $1))
    
	# Wynik jest zwiększany o kwadratową liczbę ukończonych linii
    ((score += ($1 * $1)))
    if (( score > LEVEL_UP * level)) ; then         
        ((level++))                                 
        pkill -SIGUSR1 -f "/bin/bash $0" 
    fi
    set_bold
    set_fg $SCORE_COLOR
    xyprint $SCORE_X $SCORE_Y         "Lines completed: $lines_completed"
    xyprint $SCORE_X $((SCORE_Y + 1)) "Level:           $level"
    xyprint $SCORE_X $((SCORE_Y + 2)) "Score:           $score"
    reset_colors
}

help=(
"    s: rotate"
"a: left,  d: right"
"    space: drop"
"      q: quit"
)

help_on=1 

draw_help() {
    local i s

    set_bold
    set_fg $HELP_COLOR
    for ((i = 0; i < ${#help[@]}; i++ )) {
        # przypisanie trójskładnikowe: jeśli help_on to 1, używanie łańcucha tak jak jest, w przeciwnym razie zastąp wszystkie znaki spacjami
        ((help_on)) && s="${help[i]}" || s="${help[i]//?/ }"
        xyprint $HELP_X $((HELP_Y + i)) "$s"
    }
    reset_colors
}

piece_data=(
"1256"             # kwadrat
"159d4567"         # line
"45120459"         # s
"01561548"         # z
"159a845601592654" # l
"159804562159a654" # odwrócony l
"1456159645694159" # t
)

draw_piece() {
    # Argumenty:
    # 1 - x, 2 - y, 3 - typ, 4 - obrót, 5 - zawartość komórki
    local i x y c

    # przelotowe komórki: 4 komórki, każda ma 2 współrzędne
    for ((i = 0; i < 4; i++)) {
        c=0x${piece_data[$3]:$((i + $4 * 4)):1}
        # współrzędne względne są pobierane na podstawie orientacji i dodawane do współrzędnych bezwzględnych
        ((x = $1 + (c & 3) * 2))
        ((y = $2 + (c >> 2)))
        xyprint $x $y "$5"
    }
}

next_piece=0
next_piece_rotation=0
next_piece_color=0

next_on=1 

draw_next() {
    local s="$filled_cell" visible=${1:-$next_on}
    ((visible)) && {
        set_fg $next_piece_color
        set_bg $next_piece_color
    } || {
        s="${s//?/ }"
    }
    draw_piece $NEXT_X $NEXT_Y $next_piece $next_piece_rotation "$s"
    reset_colors
}


draw_current() {
    # Argumenty: 1 - ciąg do rysowania pojedynczej komórki
    # współczynnik 2 dla x, ponieważ każda komórka ma 2 znaki szerokości
    draw_piece $((current_piece_x * 2 + PLAYFIELD_X)) $((current_piece_y + PLAYFIELD_Y)) $current_piece $current_piece_rotation "$1"
}

show_current() {
    set_fg $current_piece_color
    set_bg $current_piece_color
    draw_current "${filled_cell}"
    reset_colors
}

clear_current() {
    draw_current "${empty_cell}"
}

new_piece_location_ok() {
    # Argumenty: 1 - nowa współrzędna x elementu, 2 - nowa współrzędna y elementu
    # Sprawdź, czy kawałek można przenieść do nowej lokalizacji
    local i c x y x_test=$1 y_test=$2

    for ((i = 0; i < 4; i++)) {
        c=0x${piece_data[$current_piece]:$((i + current_piece_rotation * 4)):1}
        ((y = (c >> 2) + y_test))
        ((x = (c & 3) + x_test))
        ((y < 0 || y >= PLAYFIELD_H || x < 0 || x >= PLAYFIELD_W )) && return 1 # sprawdź, czy jesteśmy poza polem gry
        ((((playfield[y] >> (x * 3)) & 7) != 0 )) && return 1                  # sprawdź, czy lokalizacja jest już zajęta
    }
    return 0
}

get_random_next() {
    
    current_piece=$next_piece
    current_piece_rotation=$next_piece_rotation
    current_piece_color=$next_piece_color
    ((current_piece_x = (PLAYFIELD_W - 4) / 2))
    ((current_piece_y = 0))
    # Sprawdź, czy kawałek może zostać umieszczony w tym miejscu, jeśli nie - gra się kończy
    new_piece_location_ok $current_piece_x $current_piece_y || cmd_quit
    show_current

    draw_next 0
    # teraz zdobądź następny kawałek
    ((next_piece = RANDOM % ${#piece_data[@]}))
    ((next_piece_rotation = RANDOM % (${#piece_data[$next_piece]} / 4)))
    ((next_piece_color = colors[RANDOM % ${#colors[@]}]))
}

draw_border() {
    local i x1 x2 y

    set_bold
    set_fg $BORDER_COLOR
    ((x1 = PLAYFIELD_X - 2))               # 2 jest tutaj, ponieważ granica ma 2 znaki
    ((x2 = PLAYFIELD_X + PLAYFIELD_W * 2)) # 2 jest tutaj, ponieważ każda komórka na polu gry ma 2 znaki szerokości
    for ((i = 0; i < PLAYFIELD_H + 1; i++)) {
        ((y = i + PLAYFIELD_Y))
        xyprint $x1 $y "<|"
        xyprint $x2 $y "|>"
    }

    ((y = PLAYFIELD_Y + PLAYFIELD_H))
    for ((i = 0; i < PLAYFIELD_W; i++)) {
        ((x1 = i * 2 + PLAYFIELD_X)) 
        xyprint $x1 $y '=='
        xyprint $x1 $((y + 1)) "\/"
    }
    reset_colors
}

redraw_screen() {
    update_score 0
    draw_help
    draw_border
    redraw_playfield
    show_current
}

toggle_color() {
    ((use_color ^= 1))
    redraw_screen
}

init() {
    local i

    # pole gry jest inicjowane przez -1j (puste komórki)
    for ((i = 0; i < PLAYFIELD_H; i++)) {
        playfield[$i]=0
    }

    clear
    hide_cursor
    get_random_next
    get_random_next
    redraw_screen
}

# ta funkcja działa w oddzielnym procesie
# wysyła polecenia DOWN do kontrolera z odpowiednim opóźnieniem
ticker() {
    # na SIGUSR2 ten proces powinien się zakończyć
    trap exit SIGUSR2
    # na opóźnienie SIGUSR1 powinno zostać zmniejszone, dzieje się to podczas podwyższenia poziomu
    trap 'DELAY=$(($DELAY * $DELAY_FACTOR))' SIGUSR1

    while true ; do echo -n $DOWN; sleep $((DELAY / 1000)).$((DELAY % 1000)); done
}

reader() {
    trap exit SIGUSR2 
    trap '' SIGUSR1   # SIGUSR1 jest ignorowany
    local -u key a='' b='' cmd esc_ch=$'\x1b'
    # polecenia to tablica asocjacyjna, która mapuje wciśnięte klawisze do poleceń, wysyłane do kontrolera
    declare -A commands=([A]=$ROTATE [C]=$RIGHT [D]=$LEFT
        [_S]=$ROTATE [_A]=$LEFT [_D]=$RIGHT
        [_]=$DROP [_Q]=$QUIT )

    while read -s -n 1 key ; do
        case "$a$b$key" in
            "${esc_ch}["[ACD]) cmd=${commands[$key]} ;; 
            *${esc_ch}${esc_ch}) cmd=$QUIT ;;           
            *) cmd=${commands[_$key]:-} ;;              
        esac
        a=$b
        b=$key
        [ -n "$cmd" ] && echo -n "$cmd"
    done
}


# ta funkcja aktualizuje zajęte komórki w tablicy pola gry po upuszczeniu elementu
flatten_playfield() {
    local i c x y
    for ((i = 0; i < 4; i++)) {
        c=0x${piece_data[$current_piece]:$((i + current_piece_rotation * 4)):1}
        ((y = (c >> 2) + current_piece_y))
        ((x = (c & 3) + current_piece_x))
        ((playfield[y] |= (current_piece_color << (x * 3))))
    }
}

# ta funkcja pobiera numer wiersza jako argument i sprawdza, czy ma puste komórki
line_full() {
    local row=${playfield[$1]} x
    for ((x = 0; x < PLAYFIELD_W; x++)) {
        ((((row >> (x * 3)) & 7) == 0)) && return 1
    }
    return 0
}

# ta funkcja przechodzi przez tablicę pola gry i eliminuje linie bez pustych komórek
process_complete_lines() {
    local y complete_lines=0
    for ((y = PLAYFIELD_H - 1; y > -1; y--)) {
        line_full $y && {
            unset playfield[$y]
            ((complete_lines++))
        }
    }
    for ((y = 0; y < complete_lines; y++)) {
        playfield=(0 ${playfield[@]})
    }
    return $complete_lines
}

process_fallen_piece() {
    flatten_playfield
    process_complete_lines && return
    update_score $?
    redraw_playfield
}

move_piece() {
# argumenty: 1 - nowa współrzędna x, 2 - nowa współrzędna y
# jeśli to możliwe, przenosi element do nowej lokalizacji
    if new_piece_location_ok $1 $2 ; then 
        clear_current                     
        current_piece_x=$1                
        current_piece_y=$2                
        show_current                      
        return 0                          
    fi                                    
    (($2 == current_piece_y)) && return 0 
    process_fallen_piece                  
    get_random_next                       
    return 1
}

cmd_right() {
    move_piece $((current_piece_x + 1)) $current_piece_y
}

cmd_left() {
    move_piece $((current_piece_x - 1)) $current_piece_y
}

cmd_rotate() {
    local available_rotations old_rotation new_rotation

    available_rotations=$((${#piece_data[$current_piece]} / 4))       # liczba orientacji dla tego elementu
    old_rotation=$current_piece_rotation                              # zachować aktualną orientację
    new_rotation=$(((old_rotation + 1) % available_rotations))        # oblicz nową orientację
    current_piece_rotation=$new_rotation                              # set orientation to new
    if new_piece_location_ok $current_piece_x $current_piece_y ; then # sprawdź, czy nowa orientacja jest w porządku
        current_piece_rotation=$old_rotation                          # jeśli tak - przywróć starą orientację
        clear_current                                                 # wyraźny obraz jednostkowy
        current_piece_rotation=$new_rotation                          # ustaw nową orientację
        show_current                                                  # rysuj kawałek z nową orientacją
    else                                                             
        current_piece_rotation=$old_rotation                          
    fi
}

cmd_down() {
    move_piece $current_piece_x $((current_piece_y + 1))
}

cmd_drop() {
  
    # to przykład pętli do..while w bashu
    # ciało pętli jest puste
    # Warunek  pętli jest wykonywany przynajmniej raz
    # loop działa dopóki warunek pętli nie zwróci niezerowego kodu wyjścia
    while move_piece $current_piece_x $((current_piece_y + 1)) ; do : ; done
}

cmd_quit() {
    showtime=-1                                  
    pkill -SIGUSR2 -f "/bin/bash $0" 
    xyprint $GAMEOVER_X $GAMEOVER_Y "Game over!"
    echo -e "$screen_buffer"          
}

controller() {
    # SIGUSR1 oraz SIGUSR2 ignorujemy
    trap '' SIGUSR1 SIGUSR2
    local cmd commands

    commands[$QUIT]=cmd_quit
    commands[$RIGHT]=cmd_right
    commands[$LEFT]=cmd_left
    commands[$ROTATE]=cmd_rotate
    commands[$DOWN]=cmd_down
    commands[$DROP]=cmd_drop

    init

    while ((showtime == 1)) ; do  
        echo -ne "$screen_buffer" 
        screen_buffer=""          
        read -s -n 1 cmd          
        ${commands[$cmd]}         
    done
}

stty_g=$(stty -g) # zapiszmy stan terminalu

# wyjście tickera i czytnika jest dołączane i przesyłane do kontrolera
(
    ticker & # ticker działa jako oddzielny proces
    reader
)|(
    controller
)

show_cursor
stty $stty_g # przywróćmy stan terminalu
