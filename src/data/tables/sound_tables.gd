class_name SoundTables
extends Resource
## v3.0e sound tables identified by the executable's sound-initialization arguments.

const BANK_ADDRESS: int = 0x46f890
const GROUP_ADDRESS: int = 0x46f920
const MUSIC_PITCH_ADDRESS: int = 0x470f20
const SAMPLE_ADDRESS: int = 0x46f938

## Checkpoint and completion music pitch per level.
@export var music_pitches: Array[Vector2i] = []
## Header and body resource ids of each sound bank.
@export var banks: Array[Vector2i] = []
## First and last voice of each sound group.
@export var groups: Array[Vector2i] = []
## Sample rows in sound-id order.
@export var samples: Array[SoundSampleEntry] = []
## Why the tables could not be read, or "".
@export var error: String = ""
