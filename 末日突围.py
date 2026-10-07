extends Node
var bgm_player：AudioStreamPlayer
var sfx_pool:Array[AudioStreamPlayer]=[]
const SFX_COUNT :=8
func_ready():
    bgm_player=AudioStreamplayer.new()
    add_child(bgm_player)
    var bgm=_try_load("res://audio/bgm.ogg")
    if bgm!=null:
        bgm_player.stream=bgm
        bgm_player.play()
    for i in SFX_COUNT:
        var p:=AudioStreamPlayer.new()
        add_child(p)
        sfx_pool.adppend(p)
func _try_load(path:String) -> Audiostream:
    if ResourceLoader.exists(path):
        return load(path) as AudioStream
    return null
func play_sfx(name:String):
    var sream:=_try)load("res//audio/"+name+'.ogg')
    if stream!=null:
        for p in sfx_pool:
            if not p.playing:
                p.stream=stream
                p.play()
                return
extends Area2D
var direction:=Vecter.RIGHT
const SPEED:=800.0
var life:=50
var owner_node:=Node=null
func_ready():
    var img:=image_create(24,8,false,Image.FORMAT_RGBA8)
    img.fill(Color(1.0,0.9,0.15))
    $Sprite2D.texture=ImageTexture.create_from_image(img)
    $Sprite2D.texture_filter=CanvasItem.TEXYURE_FILTER_NEAREST
