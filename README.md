# Bartop
**Highly configurable system monitoring modules for waybar.**

View per-core CPU usage, load, memory usage, disk usage, network speed and more at a glance.

### Modules
- bartop-cpu
- bartop-memory
- bartop-disk
- bartop-network

## Installation
Clone the repository:
```bash
# https
git clone https://github.com/njfletcher215/bartop.git

# ssh
git clone git@github.com:njfletcher215/bartop.git
```

Install dependencies (jq) using your package manager:
```bash
# ubuntu
sudo apt install jq

# gentoo
sudo emerge jq
```

Then, simply run the quick installer:
```bash
cd bartop
sudo ./install.sh
```
Or manually install:
```bash
sudo install -m 0644 src/bartop.sh /usr/bin/bartop
sudo install -m 0644 src/bartop-poll.sh /usr/bin/bartop-poll
sudo install -m 0644 src/bartop-read.sh /usr/bin/bartop-read

# skip if re-installing and these files already exist
mkdir ~/.config/bartop
cp example-config.json ~/.config/bartop/config.json
cp example-waybar-config.jsonc ~/.config/bartop/waybar-config.jsonc
```
Finally, import `~/.config/bartop/waybar-config.jsonc` at the top of your waybar config:
```jsonc
{
	"include": [
		"~/.config/bartop/waybar-config.jsonc",
		...  // the rest of your imports
	],
...
```
and, of course, specify which modules you want:
```jsonc
...
	"modules-left": [
		"custom/bartop-cpu",
		"custom/bartop-network",
		...  // the rest of your modules
	],
...
```
or use the bartop group, which includes all modules:
```jsonc
...
	"modules-left": [
		"group/bartop"
		...  // the rest of your modules
	],
...
```

## Configuration
### waybar-config.jsonc
Configuration of the standard custom waybar module properties can be done via `~/.config/bartop/waybar-config.jsonc`. The `"exec": "bartop <widget-name>"` and `"return-type": "json"` fields are required for the modules to work, but everything else can be adjusted. For example: by default, every module runs btop in the user's preferred terminal on-click:
```jsonc
...
	"custom/bartop-cpu": {
		"exec": "bartop cpu",
		"return-type": "json",
		"on-click": "$TERMINAL btop"
	},
...
```
to change that to htop:
```jsonc
...
	"custom/bartop-cpu": {
		"exec": "bartop cpu",
		"return-type": "json",
		"on-click": "$TERMINAL htop"
	},
...
```
or to display " " as an icon when cpu usage is above 50%:
```jsonc
...
	"custom/bartop-cpu": {
		"exec": "bartop cpu",
		"return-type": "json",
		"on-click": $TERMINAL btop",
		"format": "{icon} {text}",
		"format-icons": ["", " "]
	},
...
```
see [the waybar wiki](https://github.com/Alexays/Waybar/wiki/Module:-Custom) for more information about configuring custom waybar modules.

### config.json
Configuration of the poll and read scripts is instead done via `~/.config/bartop/config.json`. Waybar expects modules with a return type of `json` to output data in the form `{"text": "$text", "alt": "$alt", "tooltip": "$tooltip", "class": "$class", "percentage": $percentage }` -- this is where you can configure the values for `$text`, `$tooltip`, and `$percentage`.
> **NOTE** returning `alt` and `class` is not yet supported.
Under `poll`:
```json
{
	"poll": {
		"time": 5,
		"logfile": "/tmp/bartop/last-glance.json",
		"plugins": "cpu,percpu,load,mem,memswap,fs,network,gpu"
	},
...
```
- `time` sets the time between polls.
- `logfile` sets the file that the poll script will write to and the read scripts will read from. It is recommended that you place the logfile in its own directory -- the read scripts will watch its *parent directory* for changes to know when to update.
- `plugins` sets the glances plugins that the poll script will use. Any plugins required by a widget should be included here.

Under `wigets`:
```json
...
	"widgets": {
		...
		"memory": {
			"format": "  {mem.percent}%",
			"tooltip_format": "Used:\t{mem.used} / {mem.total} ({mem.percent}%)\nAvailable:\t{mem.available}\nCache:\t{mem.cached}",
			"percentage_format": "{mem.percent}",
			"plugins": "mem"
		},
		...
        },
...
```
> **NOTE** each widget takes the same parameters (even network, though it does not have a `percentage_format` defined by default as there is no percentage network field) -- memory is simply being used as an example here because it has the fewest fields and thus is the simplest widget by default.

- `format` is the format string for `$text`.
- `tooltip-format` is the format string for `$tooltip`.
- `percentage-format` is the format string for `$percentage`. Since `$percentage` is expected to be a number, this option should consist of *only* a single format key, with no additional text (not even a '%').
- `plugins` sets the glances plugins that the read script will use. Any plugins required by the widget should be included here.

Each format string consists of normal text interspersed with *format keys*. For multiline output (useful in tooltips), `\n` may be used to denote a line break (similarly, `\t` may be used to denote a tab).

Each format key consists of two or more fields: a plugin, and one or more fields. For example, `"{mem.percent}"` is replaced at runtime with the value of the "percent" field from the "mem" plugin. If you want to print the literal phrase "{mem.percent}", escape the opening brace: `"\{mem.percent}"`. To view all available fields, look at the logfile:
```bash
cat /tmp/bartop/last-glance.json
```
> **NOTE** there are a few fields that may not behave as you expect: `mem.free` does *not* accurately display free memory, but rather available memory (same as `mem.available`); and `network[n].alias` does *not* use the system-wide alias for the network interface, but rather the alias defined by the glances config. These are quirks specific to the underlying `glances` call, and may be fixed in a later release.

More precisely, each format key is a jq filter applied to the json object found in the logfile (with the leading '.' stripped for convenience). This means more complex queries can be constructed within the format key. This is useful for the disk and network widgets, which return arrays of devices in a non-deterministic order. For example:
```json
...
	"memory": {
		"format": "  {fs[] | select(.mnt_point == \"/\") | .percent}%",
		...
	},
...
```
can be used to always set `$text` to the percent disk usage for the root partition.
> **NOTE** while this is the preferred way of querying arrays, it is not implemented by default, as everyone's device and network interface names are different. Instead, the default configuration for the disk widget uses the 0th entry, assuming it will *almost* always be the root partition, and the default configuration for the network widget uses the 1st entry, assuming it will *almost* always be the first non-loopback interface (and most likely the active one). If your find this doesn't work for you, it is suggested that you filter disk entries by `.mnt_point` or `.device_name`, and network entries by `.interface_name`. See the [multiple named disks example configuration](#multiple-named-disks).

#### Example Configurations
##### 24-Core CPU
```json
"cpu": {
    "format": "  {cpu.total}%",
    "tooltip_format": "Usage\nUser: {cpu.user}%\tSys: {cpu.system}%\t\t\t\tTotal: {cpu.total}%\n\nCores\nC0:\t{percpu[0].total}%\tC1:\t{percpu[1].total}%\tC2:\t{percpu[2].total}%\tC3:\t{percpu[3].total}%\nC4:\t{percpu[4].total}%\tC5:\t{percpu[5].total}%\tC6:\t{percpu[6].total}%\tC7:\t{percpu[7].total}%\nC8:\t{percpu[8].total}%\tC9:\t{percpu[9].total}%\tC10:\t{percpu[10].total}%\tC11:\t{percpu[11].total}%\nC12:\t{percpu[12].total}%\tC13:\t{percpu[13].total}%\tC14:\t{percpu[14].total}%\tC15:\t{percpu[15].total}%\nC16:\t{percpu[16].total}%\tC17:\t{percpu[17].total}%\tC18:\t{percpu[18].total}%\tC19:\t{percpu[19].total}%\nC20:\t{percpu[20].total}%\tC21:\t{percpu[21].total}%\tC22:\t{percpu[22].total}%\tC23:\t{percpu[23].total}%\n\nLoad Averages\n1m: {load.min1}\t5m: {load.min5}\t15m: {load.min15}",
    "percentage_format": "{cpu.total}",
    "plugins": "cpu,percpu,load"
}
```

##### Memory with Swap
```json
"memory": {
    "format": "  {mem.percent}%",
    "tooltip_format": "Used:\t{mem.used} / {mem.total} ({mem.percent}%)\nAvailable:\t{mem.available}\nCache:\t{mem.cached}\nSwap:\t{memswap.used} / {memswap.total} ({memswap.percent}%)",
    "percentage_format": "{mem.percent}",
    "plugins": "mem,memswap"
}
```

##### Multiple Disks
> **NOTE** only one percentage can be returned per-module, so if you wish to style each disk component based on the amount of free space left, multiple disk components are required.
```json
"disk": {
    "format": "  {fs[0].mnt_point}: {fs[0].percent}%   {fs[1].mnt_point}: {fs[1].percent}%   {fs[2].mnt_point}: {fs[2].percent}%",
    "tooltip_format": "Device: {fs[0].device_name} ({fs[0].fs_type})\nMount Point: {fs[0].mnt_point}\nUsed: {fs[0].used}/{fs[0].size} ({fs[0].percent}%)\nFree: {fs[0].free}\n\nDevice: {fs[1].device_name} ({fs[1].fs_type})\nMount Point: {fs[1].mnt_point}\nUsed: {fs[1].used}/{fs[1].size} ({fs[1].percent}%)\nFree: {fs[1].free}\n\nDevice: {fs[2].device_name} ({fs[2].fs_type})\nMount Point: {fs[2].mnt_point}\nUsed: {fs[2].used}/{fs[2].size} ({fs[2].percent}%)\nFree: {fs[2].free}",
    "percentage_format": "{fs[0].percent}",
    "plugins": "fs"
}
```

##### Multiple Disk Components
```json
"disk-0": {
    "format": " {fs[0].percent}%",
    "tooltip_format": "Device: {fs[0].device_name} ({fs[0].fs_type})\nMount Point: {fs[0].mnt_point}\nUsed: {fs[0].used}/{fs[0].size} ({fs[0].percent}%)\nFree: {fs[0].free}",
    "percentage_format": "{fs[0].percent}",
    "plugins": "fs"
},
"disk-1": {
    "format": " {fs[1].percent}%",
    "tooltip_format": "Device: {fs[1].device_name} ({fs[1].fs_type})\nMount Point: {fs[1].mnt_point}\nUsed: {fs[1].used}/{fs[1].size} ({fs[1].percent}%)\nFree: {fs[1].free}",
    "percentage_format": "{fs[1].percent}",
    "plugins": "fs"
}
```
and in waybar-config:
```json
"custom/bartop-disk-0": {
    "exec": "bartop disk-0",
    "return-type": "json",
    "on-click": "$TERMINAL btop"
},
"custom/bartop-disk-1": {
    "exec": "bartop disk-1",
    "return-type": "json",
    "on-click": "$TERMINAL btop"
}
```

##### Multiple Named Disks
```json
"disk": {
    "format": "  {fs[] | select(.mnt_point == \"/\") | .percent}%",
    "tooltip_format": "Device: {fs[] | select(.mnt_point == \"/\") | .device_name} ({fs[] | select(.mnt_point == \"/\") | .fs_type})\nMount Point: {fs[] | select(.mnt_point == \"/\") | .mnt_point}\nUsed: {fs[] | select(.mnt_point == \"/\") | .used}/{fs[] | select(.mnt_point == \"/\") | .size} ({fs[] | select(.mnt_point == \"/\") | .percent}%)\nFree: {fs[] | select(.mnt_point == \"/\") | .free}\n\nDevice: {fs[] | select(.mnt_point == \"/mnt/Secondary\") | .device_name} ({fs[] | select(.mnt_point == \"/mnt/Secondary\") | .fs_type})\nMount Point: {fs[] | select(.mnt_point == \"/mnt/Secondary\") | .mnt_point}\nUsed: {fs[] | select(.mnt_point == \"/mnt/Secondary\") | .used}/{fs[] | select(.mnt_point == \"/mnt/Secondary\") | .size} ({fs[] | select(.mnt_point == \"/mnt/Secondary\") | .percent}%)\nFree: {fs[] | select(.mnt_point == \"/mnt/Secondary\") | .free}",
    "percentage_format": "{fs[] | select(.mnt_point == \"/\") | .percent}",
    "plugins": "fs"
}
```

##### Multiple Network Interfaces
```json
"network": {
    "format": "  {network[0].interface_name} 󰛶  {network[0].bytes_sent_rate_per_sec}/s 󰛴  {network[0].bytes_recv_rate_per_sec}/s   {network[1].interface_name} 󰛶  {network[1].bytes_sent_rate_per_sec}/s 󰛴  {network[1].bytes_recv_rate_per_sec}/s   {network[2].interface_name} 󰛶  {network[2].bytes_sent_rate_per_sec}/s 󰛴  {network[2].bytes_recv_rate_per_sec}/s",
    "tooltip_format": "{network[0].interface_name}\nUpload: {network[0].bytes_sent} ({network[0].bytes_sent_rate_per_sec}/s)\t\tDownload: {network[0].bytes_recv} ({network[0].bytes_recv_rate_per_sec}/s)\nTotal Upload: {network[0].bytes_sent_gauge}\tTotal Download: {network[0].bytes_recv_gauge}\n\n{network[1].interface_name}\nUpload: {network[1].bytes_sent} ({network[1].bytes_sent_rate_per_sec}/s)\t\tDownload: {network[1].bytes_recv} ({network[1].bytes_recv_rate_per_sec}/s)\nTotal Upload: {network[1].bytes_sent_gauge}\tTotal Download: {network[1].bytes_recv_gauge}\n\n{network[2].interface_name}\nUpload: {network[2].bytes_sent} ({network[2].bytes_sent_rate_per_sec}/s)\t\tDownload: {network[2].bytes_recv} ({network[2].bytes_recv_rate_per_sec}/s)\nTotal Upload: {network[2].bytes_sent_gauge}\tTotal Download: {network[2].bytes_recv_gauge}",
    "plugins": "network"
}
```

##### Single Named Network Interface
```json
"network": {
    "format": "  {network[] | select(.interface_name == \"enp7s0\") | .interface_name} 󰛶  {network[] | select(.interface_name == \"enp7s0\") | .bytes_sent_rate_per_sec}/s 󰛴  {network[] | select(.interface_name == \"enp7s0\") | .bytes_recv_rate_per_sec}/s",
    "tooltip_format": "{network[] | select(.interface_name == \"enp7s0\") | .interface_name}\nUpload: {network[] | select(.interface_name == \"enp7s0\") | .bytes_sent} ({network[] | select(.interface_name == \"enp7s0\") | .bytes_sent_rate_per_sec}/s)\t\tDownload: {network[] | select(.interface_name == \"enp7s0\") | .bytes_recv} ({network[] | select(.interface_name == \"enp7s0\") | .bytes_recv_rate_per_sec}/s)\nTotal Upload: {network[] | select(.interface_name == \"enp7s0\") | .bytes_sent_gauge}\tTotal Download: {network[] | select(.interface_name == \"enp7s0\") | .bytes_recv_gauge}",
    "plugins": "network"
}
```

