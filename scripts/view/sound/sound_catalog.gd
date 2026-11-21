class_name SoundCatalog
extends RefCounted
## The sound tables (#247): which names exist, which sim message plays which sound, which room kinds
## make which ambience. View only. No audio ships in the repo: the files are loaded at run time from
## folders outside the import system (local_sounds/ beside the project, user://sounds/), and a missing
## folder or file just means silence.

const MessagesScript := preload("res://scripts/sim/messages.gd")

const BUS_AMBIENCE := &"Ambience"
const BUS_EVENTS := &"Events"
const BUS_UI := &"UI"
const BUSES: Array[StringName] = [BUS_AMBIENCE, BUS_EVENTS, BUS_UI]

## Every file name the game knows (the .wav extension is implied). Anything else in a folder is ignored.
const AMBIENCE_NAMES: Array[String] = [
	"Bird1", "Bird2", "Bird3", "Bird4", "Cricket1", "Rain", "Thunder", "Crowd1", "Crowd2", "Office1",
	"Resturant1", "Resturant2", "Resturant3", "DanceHall1",
	"Theater1", "Theater2", "Theater3", "Theater4", "Theater5", "Theater6", "Theater7", "Theater8",
	"Theater9", "Theater10", "Theater11", "Theater12", "Theater13", "Theater14", "Theater15",
	"Subway1", "Subway2", "Vacuum1", "ClockTick", "Car1", "Car2",
]
const EVENT_NAMES: Array[String] = [
	"Belltoll", "Build1", "Build2", "Buy", "Demolish", "Doorbell1", "Dunno", "NoPlop", "ElevatorMove",
	"ElevatorOpen1", "ElevatorOpen2", "Explode1", "Fire", "FireTruck1", "Helicopter", "Intro", "Recycling",
	"Santa!", "StarGet", "TerroristHello", "TerroristTY", "Wedding", "Yay1",
]

const THEATER_CLIPS: Array[String] = [
	"Theater1", "Theater2", "Theater3", "Theater4", "Theater5", "Theater6", "Theater7", "Theater8",
	"Theater9", "Theater10", "Theater11", "Theater12", "Theater13", "Theater14", "Theater15",
]
const BUILD_CLIPS: Array[String] = ["Build1", "Build2"]
const REFUSED_CLIPS: Array[String] = ["NoPlop"]
const RESCUE_CLIPS: Array[String] = ["FireTruck1", "Helicopter"]
const ELEVATOR_OPEN_CLIPS: Array[String] = ["ElevatorOpen1", "ElevatorOpen2"]
const BIRD_CLIPS: Array[String] = ["Bird1", "Bird2", "Bird3", "Bird4"]
const CROWD_CLIPS: Array[String] = ["Crowd1", "Crowd2"]
const SUBWAY_CLIPS: Array[String] = ["Subway1", "Subway2"]
const CAR_CLIPS: Array[String] = ["Car1", "Car2"]

## Sim message code -> [bus, clip names (one is picked at random)]. Codes with no row make no sound.
const MESSAGE_SOUNDS: Dictionary = {
	MessagesScript.PURCHASE_REFUSED: [&"UI", REFUSED_CLIPS],
	MessagesScript.FLOOR_REFUSED: [&"UI", REFUSED_CLIPS],
	MessagesScript.LOBBY_REFUSED: [&"UI", REFUSED_CLIPS],
	MessagesScript.ROOM_REFUSED: [&"UI", REFUSED_CLIPS],
	MessagesScript.BULLDOZE_REFUSED: [&"UI", REFUSED_CLIPS],
	MessagesScript.REPLACE_REFUSED: [&"UI", REFUSED_CLIPS],
	MessagesScript.STAIRS_REFUSED: [&"UI", REFUSED_CLIPS],
	MessagesScript.FLOOR_BUILT: [&"UI", BUILD_CLIPS],
	MessagesScript.LOBBY_BUILT: [&"UI", BUILD_CLIPS],
	MessagesScript.ROOM_BUILT: [&"UI", BUILD_CLIPS],
	MessagesScript.ROOM_REPLACED: [&"UI", BUILD_CLIPS],
	MessagesScript.STAIRS_BUILT: [&"UI", BUILD_CLIPS],
	MessagesScript.ESCALATOR_BUILT: [&"UI", BUILD_CLIPS],
	MessagesScript.ROOM_REMOVED: [&"UI", ["Demolish"]],
	MessagesScript.STAR_PROMOTED: [&"UI", ["StarGet"]],
	MessagesScript.RESCUE_ARRIVED: [&"Events", RESCUE_CLIPS],
	MessagesScript.THREAT_NOTICE: [&"Events", ["TerroristHello"]],
	MessagesScript.THREAT_PAID: [&"Events", ["TerroristTY"]],
	MessagesScript.THREAT_FOUND: [&"Events", ["TerroristTY"]],
	MessagesScript.THREAT_EXPLODED: [&"Events", ["Explode1"]],
	MessagesScript.VIP_ARRIVED: [&"Events", ["Doorbell1"]],
	MessagesScript.VIP_GOOD: [&"Events", ["Yay1"]],
	MessagesScript.VIP_BAD: [&"Events", ["Dunno"]],
	MessagesScript.CASINO_INCIDENT: [&"Events", ["Dunno"]],
	MessagesScript.GUEST_UNREACHED: [&"Events", ["Dunno"]],
	MessagesScript.TRIP_UNREACHABLE: [&"Events", ["Dunno"]],
}

## A condo is bought outright, so a ROOM_BUILT whose catalogue kind is a condo plays the purchase sound.
const CONDO_KIND := "condo"
const BUY_CLIP := "Buy"

## Sounds nothing in the sim can trigger yet (no weather, wedding, cathedral or Santa hook).
const UNMAPPED: Array[String] = ["Rain", "Thunder", "Wedding", "Belltoll", "Santa!", "ClockTick"]

## Room kind -> the ambience loop it adds to, weighted by that kind's floor area in view. A kind not
## listed is silent. Crowd, birds, crickets, fire and the elevator hum are driven by the system itself.
const KIND_LOOPS: Dictionary = {
	"housekeeping": "Vacuum1",
	"fast_food": "Resturant1", "cafe": "Resturant1", "deli": "Resturant1", "grocery": "Resturant1",
	"restaurant": "Resturant2", "pizza": "Resturant2", "sushi": "Resturant2",
	"fine_dining": "Resturant3", "bar": "Resturant3",
	"nightclub": "DanceHall1", "party_hall": "DanceHall1",
	"metro": "Subway1",
	"parking_ramp": "Car1",
}
const THEATER_KIND := "movie_theatre"
## Offices play their clip once now and then rather than looping it (owner: the phone rang far too often).
const OFFICE_KINDS: Array[String] = ["office", "coworking"]
const OFFICE_CLIP := "Office1"
const LOBBY_KIND := "lobby"
const RECYCLING_KIND := "recycling"

const CROWD_LOOP := "Crowd1"
const BIRD_LOOP := "Bird1"
const CRICKET_LOOP := "Cricket1"
const FIRE_LOOP := "Fire"
const ELEVATOR_LOOP := "ElevatorMove"


static func all_names() -> Array[String]:
	var names: Array[String] = []
	names.append_array(AMBIENCE_NAMES)
	names.append_array(EVENT_NAMES)
	return names


static func is_known(sound_name: String) -> bool:
	return sound_name in AMBIENCE_NAMES or sound_name in EVENT_NAMES


## Folders searched for sound files, in order; the first to hold a name wins: the owner's local
## override local_sounds/ (git-ignored; from a worktree under .claude/worktrees/ also the main
## checkout's, and the one beside the executable), then the committed originals in res://assets/sounds/,
## then user://sounds/. A name found nowhere is simply silent.
static func search_dirs() -> Array[String]:
	var project := ProjectSettings.globalize_path("res://")
	var dirs: Array[String] = [
		project.path_join("local_sounds"),
		project.path_join("../../../local_sounds").simplify_path(),
		OS.get_executable_path().get_base_dir().path_join("local_sounds"),
		project.path_join("assets/sounds"),
		ProjectSettings.globalize_path("user://sounds"),
	]
	return dirs


## Loads every known name found in dirs as a stream. A missing folder or an unreadable file is skipped:
## no files at all gives an empty dictionary, never an error.
static func load_streams(dirs: Array[String]) -> Dictionary:
	var streams: Dictionary = {}
	for sound_name in all_names():
		for dir in dirs:
			var path := dir.path_join(sound_name + ".wav")
			if not FileAccess.file_exists(path):
				continue
			var wav := AudioStreamWAV.load_from_file(path)
			if wav == null:
				continue
			streams[sound_name] = wav
			break
	return streams


## A copy of a WAV stream that loops over its whole length (anything else comes back unchanged).
static func make_loop(stream: AudioStream) -> AudioStream:
	var wav := stream as AudioStreamWAV
	if wav == null:
		return stream
	var looped := wav.duplicate() as AudioStreamWAV
	var bytes := 1
	if looped.format == AudioStreamWAV.FORMAT_16_BITS:
		bytes = 2
	if looped.stereo:
		bytes *= 2
	looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
	looped.loop_begin = 0
	looped.loop_end = maxi(1, looped.data.size() / bytes)
	return looped
