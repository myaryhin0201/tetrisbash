
set -u 

trap '' SIGUSR1 SIGUSR2

DELAY=1000          
DELAY_FACTOR="8/10" 

RED=1
GREEN=2
YELLOW=3
BLUE=4
FUCHSIA=5
CYAN=6
WHITE=7

PLAYFIELD_W=10
PLAYFIELD_H=20
PLAYFIELD_X=30
PLAYFIELD_Y=1
BORDER_COLOR=$YELLOW

SCORE_X=1
SCORE_Y=2
SCORE_COLOR=$GREEN

GAMEOVER_X=1
GAMEOVER_Y=$((PLAYFIELD_H + 3))

LEVEL_UP=20

colors=($RED $GREEN $YELLOW $BLUE $FUCHSIA $CYAN $WHITE)

use_color=1      
showtime=1       
empty_cell=" ."  
filled_cell="[]" 

score=0
level=1        
lines_completed=0 


puts() {
    screen_buffer+=${1}
}

xyprint() {
    puts "\033[${2};${1}H${3}"
}

show_cursor() {
    echo -ne "\033[?25h"
}

 hide_cursor() {
     echo -ne "\033[?25l"
 }

# foreground color
set_fg() {
    ((use_color)) && puts "\033[3${1}m"
}

# background color
set_bg() {
    ((use_color)) && puts "\033[4${1}m"
}

reset_colors() {
    puts "\033[0m"
}

set_bold() {
    puts "\033[1m"
}

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
 
    ((lines_completed += $1))
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

clear_current() {
    draw_current "${empty_cell}"
}

draw_border() {
    local i x1 x2 y

    set_bold
    set_fg $BORDER_COLOR
    ((x1 = PLAYFIELD_X - 2))              
    ((x2 = PLAYFIELD_X + PLAYFIELD_W * 2)) 
    for ((i = 0; i < PLAYFIELD_H + 1; i++)) {
        ((y = i + PLAYFIELD_Y))
        xyprint $x1 $y "<!"
        xyprint $x2 $y "!>"
    }

    ((y = PLAYFIELD_Y + PLAYFIELD_H))
    for ((i = 0; i < PLAYFIELD_W; i++)) {
        ((x1 = i * 2 + PLAYFIELD_X)) 
        xyprint $x1 $y '__'
        xyprint $x1 $((y + 1)) "\/"
    }
    reset_colors
}

redraw_screen() {
    update_score 0
    draw_border
    redraw_playfield
 }



init() {
    local i

    for ((i = 0; i < PLAYFIELD_H; i++)) {
        playfield[$i]=0
    }

    clear
    hide_cursor
    redraw_screen
}

reader() {
    trap exit SIGUSR2 
    trap '' SIGUSR1   
    local -u key a='' b='' cmd esc_ch=$'\x1b'


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


process_fallen_piece() {
    flatten_playfield
    process_complete_lines && return
}

controller() {
   
    trap '' SIGUSR1 SIGUSR2
   local cmd commands

    init

    while ((showtime == 1)) ; do 
        echo -ne "$screen_buffer"
        screen_buffer=""         
        read -s -n 1 cmd      
        ${commands[$cmd]}     
    done
}

stty_g=$(stty -g) 
(
    reader
)|(
    controller
)
show_cursor
stty $stty_g 
