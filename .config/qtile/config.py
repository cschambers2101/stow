# Copyright (c) 2010 Aldo Cortesi
# Copyright (c) 2010, 2014 dequis
# Copyright (c) 2012 Randall Ma
# Copyright (c) 2012-2014 Tycho Andersen
# Copyright (c) 2012 Craig Barnes
# Copyright (c) 2013 horsik
# Copyright (c) 2013 Tao Sauvage
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

from libqtile import bar, layout, widget
from libqtile.config import Click, Drag, Group, Key, Match, Screen
from libqtile.lazy import lazy
from libqtile.utils import guess_terminal
import os
import subprocess

from libqtile import hook

@hook.subscribe.startup_once
def autostart():
    home = os.path.expanduser('~/.config/qtile/autostart.sh')
    subprocess.Popen([home])

mod = "mod4"
terminal = "xfce4-terminal" #guess_terminal()
"""
Color schemes live here
"""

_gruvbox = {
    'bg':           '#22181c',
    'fg':           '#f6e8ea',
    'dark-red':     '#ea6962',
    'red':          '#e03c00',
    'dark-green':   '#a9b665',
    'green':        '#878e76',
    'dark-yellow':  '#e78a4e',
    'yellow':       '#d8a657',
    'dark-blue':    '#7daea3',
    'blue':         '#7daea3',
    'dark-magenta': '#d3869b',
    'magenta':      '#7f6a93',
    'dark-cyan':    '#89b482',
    'cyan':         '#89b482',
    'dark-gray':    '#665c54',
    'gray':         '#928374',

    'fg4':          '#766f64',
    'fg3':          '#665c54',
    'fg2':          '#504945',
    'fg1':          '#3c3836',
    'bg0':          '#32302f',
    'fg0':          '#1d2021',
    'fg9':          '#ebdbb2'
}

_craig = {
    'bg':           '#242325',
    'fg':           '#F4F4F9',
    'dark-red':     '#A52422',
    'red':          '#DE1A1A',
    'dark-green':   '#0B6E4F',
    'green':        '#36827F',
    'dark-yellow':  '#FCAF58',
    'yellow':       '#F9DC5C',
    'dark-blue':    '#007090',
    'blue':         '#01A7C2',
    'dark-magenta': '#C47AC0',
    'magenta':      '#E072A4',
    'dark-cyan':    '#119DA4',
    'cyan':         '#94E0F0',
    'dark-gray':    '#45545E',
    'golden-bronze':'#B19206',
    'olive-bark':   '#625104',
    'shadow-grey':  '#1A1A23',
    'gray':         '#6F8695',
}

color_schema = _craig

keys = [

# Add dedicated sxhkdrc to autostart.sh script

# CLOSE WINDOW, RELOAD AND QUIT QTILE
    Key([mod], "q", lazy.window.kill(), desc="Kill focused window"),
    Key([mod, "shift"], "r", lazy.reload_config(), desc="Reload the config"),
    Key([mod, "shift"], "q", lazy.shutdown(), desc="Shutdown Qtile"),
    #Key([mod], "r", lazy.spawncmd(), desc="Spawn a command using a prompt widget"),

# CHANGE FOCUS USING VIM OR DIRECTIONAL KEYS
    Key([mod], "Up", lazy.layout.up()),
    Key([mod], "Down", lazy.layout.down()),
    Key([mod], "Left", lazy.layout.left()),
    Key([mod], "Right", lazy.layout.right()),
    Key([mod], "k", lazy.layout.up()),
    Key([mod], "j", lazy.layout.down()),
    Key([mod], "h", lazy.layout.left()),
    Key([mod], "l", lazy.layout.right()),

# MOVE WINDOWS UP OR DOWN,LEFT OR RIGHT USING VIM KEYS
    Key([mod, "shift"], "k", lazy.layout.shuffle_up()),
    Key([mod, "shift"], "j", lazy.layout.shuffle_down()),
    Key([mod, "shift"], "h", lazy.layout.swap_column_left()),
    Key([mod, "shift"], "l", lazy.layout.swap_column_right()),

# MOVE WINDOWS UP OR DOWN,LEFT OR RIGHT USING DIRECTIONAL KEYS
    Key([mod, "shift"], "Up", lazy.layout.shuffle_up()),
    Key([mod, "shift"], "Down", lazy.layout.shuffle_down()),
    Key([mod, "shift"], "Left", lazy.layout.swap_column_left()),
    Key([mod, "shift"], "Right", lazy.layout.swap_column_right()),

# RESIZE UP, DOWN, LEFT, RIGHT USING VIM KEYS
    Key([mod, "control"], "l",
        lazy.layout.grow_right(),
        lazy.layout.grow(),
        lazy.layout.increase_ratio(),
        lazy.layout.delete(),
        ),
    Key([mod, "control"], "h",
        lazy.layout.grow_left(),
        lazy.layout.shrink(),
        lazy.layout.decrease_ratio(),
        lazy.layout.add(),
        ),
    Key([mod, "control"], "k",
        lazy.layout.grow_up(),
        lazy.layout.grow(),
        lazy.layout.decrease_nmaster(),
        ),
    Key([mod, "control"], "j",
        lazy.layout.grow_down(),
        lazy.layout.shrink(),
        lazy.layout.increase_nmaster(),
        ),

# RESIZE UP, DOWN, LEFT, RIGHT USING DIRECTIONAL KEYS
    Key([mod, "control"], "Right",
        lazy.layout.grow_right(),
        lazy.layout.grow(),
        lazy.layout.increase_ratio(),
        lazy.layout.delete(),
        ),
     Key([mod, "control"], "Left",
        lazy.layout.grow_left(),
        lazy.layout.shrink(),
        lazy.layout.decrease_ratio(),
        lazy.layout.add(),
        ),
     Key([mod, "control"], "Up",
        lazy.layout.grow_up(),
        lazy.layout.grow(),
        lazy.layout.decrease_nmaster(),
        ),
     Key([mod, "control"], "Down",
        lazy.layout.grow_down(),
        lazy.layout.shrink(),
        lazy.layout.increase_nmaster(),
        ),

# Go full screen with app
    Key([mod], "m", lazy.window.toggle_fullscreen()),

# QTILE LAYOUT KEYS
    Key([mod], "Tab", lazy.next_layout(), desc="Toggle between layouts"),

# TOGGLE FLOATING LAYOUT
    Key([mod, "shift"], "space", lazy.window.toggle_floating()),
	Key([mod, "shift"], "z", lazy.layout.normalize(), desc="Reset all window sizes"),

# Switch Monitors
    Key(
        ["control", "shift"], 
        "m", 
        # Use bash -c to source the environment and run the function
        lazy.spawn("/home/craigchambers/.screenlayout/monitor_toggle.sh") 
    ),
# LAUNCH PROGRAMS
    Key([mod], "b", lazy.spawn("google-chrome")), # Launch Chrome
    Key([mod], "Return", lazy.spawn(terminal)), # Launch Gnome Terminal
    Key([mod], "r", lazy.spawn("rofi -show run")), # Launch Rofi
#    Key([mod, "shift"], "l", lazy.spawn("i3lock -i .local/share/backgrounds/wallhaven-85erok_3440x1440.png")), # Launch i3lock
    Key([mod, "shift"], "l", lazy.spawn(os.path.expanduser("~/.local/bin/i3lock-screensaver.sh")), desc="Launch custom lockscreen script"),
    Key([mod, "shift"], "f", lazy.spawn("pcmanfm")), # Launch PCManFM
    Key([mod, "shift"], "m", lazy.spawn("xfce4-terminal -e alsamixer")), # Launch alsamixer,
    Key([mod], "Print", lazy.spawn("flameshot gui"), desc="Launch FlameshotGUI"),
    Key([mod, "shift"], "s", lazy.spawn(os.path.expanduser("~/.local/bin/set-wallpaper.sh")), desc="Launch custom wallpaper changer script"),
    Key([mod, "shift"], "n", lazy.spawn("dunstctl set-paused toggle"), desc="Toggle Do Not Disturb")
]
# end of keys

#groups = [Group(i) for i in ["", "", "", "", "阮", "", "", "", ""]]
groups = [Group(i) for i in ["1", "2", "3", "4", "5", "6", "7", "8", "9"]]
group_hotkeys = "123456789"

for i in groups:
    keys.extend(
        [
            # mod1 + letter of group = switch to group
            Key(
                [mod],
                i.name,
                lazy.group[i.name].toscreen(),
                desc="Switch to group {}".format(i.name),
            ),
            # mod1 + shift + letter of group = switch to & move focused window to group
            Key(
                [mod, "shift"],
                i.name,
                lazy.window.togroup(i.name, switch_group=True),
                desc="Switch to & move focused window to group {}".format(i.name),
            ),
            # Or, use below if you prefer not to switch to that group.
            # # mod1 + shift + letter of group = move focused window to group
            # Key([mod, "shift"], i.name, lazy.window.togroup(i.name),
            #     desc="move focused window to group {}".format(i.name)),
        ]
    )

layouts = [
    layout.MonadTall(margin = 10, border_focus=color_schema['shadow-grey'], border_normal=color_schema['bg'], border_width=4),
    layout.MonadWide(margin = 10, border_focus=color_schema['shadow-grey'], border_normal=color_schema['bg'], border_width=4),
    # layout.Columns(margin=10, num_columns=4, insert_position=1,
    # border_focus=color_schema['shadow-grey'],
    # border_normal=color_schema['bg'], border_width=4),
    # layout.Matrix(),
    layout.Max(margin = 10, border_normal=color_schema['bg']),
    # Try more layouts by unleashing below layouts.
    # layout.Stack(num_stacks=2),
    # layout.Bsp(),
    # layout.Matrix(),
    # layout.RatioTile(),
    # layout.Tile(),
    # layout.TreeTab(),
    # layout.VerticalTile(),
    # layout.Zoomy(),
]

widget_defaults = dict(
    font='Hack Nerd Font Regular',
    background=color_schema['bg'],
    foreground=color_schema['fg'],
    fontsize=14,
    padding=6,
)
extension_defaults = widget_defaults.copy()
separator = widget.Sep(size_percent=50, foreground=color_schema['dark-gray'], linewidth =1, padding =10)
spacer = widget.Sep(size_percent=50, foreground=color_schema['fg'], linewidth =0, padding =10)

# --- BATTERY WIDGET CONDITIONAL CHECK ---
# Define the path to check. Use 'BAT0' as a starting point.
# You may need to change 'BAT0' to 'BAT1' or another path depending on your laptop.
BATTERY_DIR = '/sys/class/power_supply/BAT0'
battery_widget = []

if os.path.isdir(BATTERY_DIR):
    # If the directory exists (on the laptop), define the widget
    print("Battery detected. Including Battery widget.")
    battery_widget = [
        separator, # Add a separator before the battery widget
        widget.Battery(
            format='{char} {percent:2.0%}',
            # --- ICONS ---
            charge_char='󰂄',       # Icon when plugged in
            discharge_char='󰁹',    # Icon when unplugged
            full_char='󰚥',         # Icon when 100% full
            empty_char='󰂎',         # Icon when 0%
            
            update_interval=5,
            # --- COLORS ---
            foreground=color_schema['fg'],
            background=color_schema['bg'],
            low_foreground=color_schema['red'],
            low_percentage=0.20,
            
            # Since the path exists, it should auto-detect. 
            # If you still get an error, uncomment the line below 
            # and verify the path you found in the previous answer.
            # battery='BAT0',
        ),
    ]
else:
    # If the directory does NOT exist (on the desktop), define an empty list
    print("No battery detected. Skipping Battery widget.")
    battery_widget = []

# Initialize the base widgets list
widgets_list = [
    widget.GroupBox(
        disable_drag=True,
        use_mouse_wheel=False,
        active=color_schema['fg'],
        inactive=color_schema['dark-gray'],
        highlight_method='line',
        this_current_screen_border=color_schema['dark-green'],
        hide_unused = False,
        rounded = False,
        urgent_alert_method='line',
        urgent_text=color_schema['dark-red']
    ),
    widget.WindowName(),
    widget.CheckUpdates(
        distro='Debian',
        colour_have_updates=color_schema['yellow'],
        colour_no_updates=color_schema['fg'],
        display_format='  Updates: {updates}',
        no_update_string= '  Updates: 0'
    ),
    separator,
    widget.CPU(
        format="  {load_percent:04}%",
        foreground=color_schema['fg'],
    ),
    separator,
    widget.Memory(
        format='󰻠 {MemUsed: .0f}{mm}/{MemTotal: .0f}{mm}',
        measure_mem='G',
        foreground=color_schema['fg']
    ),
    separator,
    *battery_widget,
    separator,
    widget.Volume(
        fmt="󰕾 {}",
        mute_command="amixer -D pulse set Master toggle",
        foreground=color_schema['fg'],
        volume_app="xfce4-terminal -e alsamixer"
    ),
    separator,
    widget.Clock(format=' %a, %b %-d',
        foreground=color_schema['fg']
    ),
    widget.Clock(format='%-I:%M %p',
        foreground=color_schema['fg']
    ),
    separator,
    widget.CurrentLayout(
        scale=0.5,
        padding=0,
        foreground=color_schema['fg']
    ),
    separator,
    widget.Systray(
        padding = 6,
        foreground=color_schema['fg']
    ),
    spacer,
]

screens = [
    Screen(top=bar.Bar(widgets=widgets_list, size=40)),
]

# Drag floating layouts.
mouse = [
    Drag([mod], "Button1", lazy.window.set_position_floating(), start=lazy.window.get_position()),
    Drag([mod], "Button3", lazy.window.set_size_floating(), start=lazy.window.get_size()),
    Click([mod], "Button2", lazy.window.bring_to_front()),
]

dgroups_key_binder = None
dgroups_app_rules = []  # type: list
follow_mouse_focus = True
bring_front_click = False
cursor_warp = False
floating_layout = layout.Floating(
    float_rules=[
        # Run the utility of `xprop` to see the wm class and name of an X client.
        *layout.Floating.default_float_rules,
        Match(wm_class="qimgv"),  # q image viewer
        Match(wm_class="Galculator"),  # calculator
        Match(wm_class="confirmreset"),  # gitk
        Match(wm_class="makebranch"),  # gitk
        Match(wm_class="maketag"),  # gitk
        Match(wm_class="ssh-askpass"),  # ssh-askpass
        Match(title="branchdialog"),  # gitk
        Match(title="pinentry"),  # GPG key password entry
    ]
)
auto_fullscreen = True
focus_on_window_activation = "smart"
reconfigure_screens = True

# If things like steam games want to auto-minimize themselves when losing
# focus, should we respect this or not?
auto_minimize = True

# When using the Wayland backend, this can be used to configure input devices.
wl_input_rules = None

# XXX: Gasp! We're lying here. In fact, nobody really uses or cares about this
# string besides java UI toolkits; you can see several discussions on the
# mailing lists, GitHub issues, and other WM documentation that suggest setting
# this string if your java app doesn't work correctly. We may as well just lie
# and say that we're a working one by default.
#
# We choose LG3D to maximize irony: it is a 3D non-reparenting WM written in
# java that happens to be on java's whitelist.
wmname = "LG3D"
