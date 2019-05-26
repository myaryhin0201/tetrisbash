set -u 

trap '' SIGUSR1 SIGUSR2

PLAYFIELD_W=10
PLAYFIELD_H=20
PLAYFIELD_X=30
PLAYFIELD_Y=1
showtime=1       # controller runs while this flag is 1
empty_cell=" ."  # how we draw empty cell
filled_cell="[]" # how we draw filled cell

puts() {
    screen_buffer+=${1}
}

xyprint() {
    puts "\033[${2};${1}H${3}"
}

 hide_cursor() {
     echo -ne "\033[?25l"
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
             fi
        }
    }
}

next_piece=0
next_piece_rotation=0
next_piece_color=0



show_current() {
    set_fg $current_piece_color
    set_bg $current_piece_color
    draw_current "${filled_cell}"
	}

clear_current() {
    draw_current "${empty_cell}"
}

draw_border() {
    local i x1 x2 y

    ((x1 = PLAYFIELD_X - 2))              
    ((x2 = PLAYFIELD_X + PLAYFIELD_W * 2)) 
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
  }

redraw_screen() {
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
        a=$b   # preserve previous keys
        b=$key
        [ -n "$cmd" ] && echo -n "$cmd"
    done
}

flatten_playfield() {
    local i c x y
    for ((i = 0; i < 4; i++)) {
        c=0x${piece_data[$current_piece]:$((i + current_piece_rotation * 4)):1}
        ((y = (c >> 2) + current_piece_y))
        ((x = (c & 3) + current_piece_x))
        ((playfield[y] |= (current_piece_color << (x * 3))))
    }
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
