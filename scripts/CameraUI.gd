# CameraUI.gd
extends Control

signal permission_granted

const FEED_INDEX: int = 0
const FORMAT_INDEX: int = 0

@onready var camera_view: TextureRect = $PanelContainer/VBoxContainer/CameraView

var shader_material: ShaderMaterial = null
var texture: Texture2D = null
var rgb_texture: CameraTexture = null
var y_texture: CameraTexture = null
var cbcr_texture: CameraTexture = null

func _ready() -> void:
	# Load and prepare ShaderMaterial
	shader_material = camera_view.material
	permission_granted.connect(setup_camera)

# Release camera when the node is removed from the tree
func _exit_tree() -> void:
	stop_camera()

# Camera initialization function called from Main.gd
func initialize_camera() -> void:
	print("CameraUI: Initializing camera")
	if OS.get_name() in ["Android", "iOS"]:
		var permissions := OS.get_granted_permissions()
		for p in permissions:
			print("granted: %s" % p)
		if OS.request_permission("CAMERA"):
			permission_granted.emit()
		else:
			print("Camera permission denied.")
		return
	permission_granted.emit()

# Camera stop function called from Main.gd
func stop_camera() -> void:
	print("CameraUI: Stopping YCbCr camera...")

	# Clear TextureRect material and texture (optional)
	if is_instance_valid(camera_view): # Check if the node is valid
		camera_view.material = null
		camera_view.texture = null # Usually not necessary when using material
	texture = null
	rgb_texture = null
	y_texture = null
	cbcr_texture = null

func print_feeds(feeds: Array[CameraFeed]) -> void:
	print("-".repeat(20))
	for f in feeds:
		print("%d / %s / %s / %s / %s" % [f.get_id(), f.get_name(), f.get_position(), f.get_class(), f.get_datatype()])
	print("-".repeat(20))

func print_formats(formats: Array) -> void:
	print("-".repeat(20))
	for f in formats:
		print(f)
	print("-".repeat(20))

func prints_datatype(dt: CameraFeed.FeedDataType) -> String:
	match dt:
		CameraFeed.FeedDataType.FEED_NOIMAGE:
			return "NOIMAGE"
		CameraFeed.FeedDataType.FEED_RGB:
			return "RGB"
		CameraFeed.FeedDataType.FEED_YCBCR:
			return "YCBCR"
		CameraFeed.FeedDataType.FEED_YCBCR_SEP:
			return "YCBCR_SEP"
		CameraFeed.FeedDataType.FEED_EXTERNAL:
			return "EXTERNAL"
		_:
			return "UNKNOWN"

# Find and set up YCbCr camera feed
func setup_camera() -> void:
	print("setup_camera")
	var feeds := CameraServer.feeds()
	if feeds.is_empty():
		print("no cameras")
		return
	print_feeds(feeds)
	var feed := feeds[FEED_INDEX]
	print("selected feed: %d / %s / %s / %s / %s" % [feed.get_id(), feed.get_name(), feed.get_position(), feed.get_class(), feed.get_datatype()])

	if OS.get_name() != "macOS":
		var formats := feed.get_formats()
		if formats.is_empty():
			print("no formats")
			return
		print_formats(formats)
		feed.set_format(FORMAT_INDEX, {})
		print("selected format: %s" % formats[FORMAT_INDEX])

	# Set texture to shader
	if shader_material:
		var id := feed.get_id()
		rgb_texture = shader_material.get_shader_parameter("rgb_texture")
		y_texture = shader_material.get_shader_parameter("y_texture")
		cbcr_texture = shader_material.get_shader_parameter("cbcr_texture")

		var _on_frame_changed = func() -> void:
			print("called frame_changed")
			var dt := feed.get_datatype()
			print("datatype: %s" % prints_datatype(dt))
			var s2 := Vector2.ZERO
			match dt:
				CameraFeed.FeedDataType.FEED_RGB:
					rgb_texture.camera_feed_id = id
					shader_material.set_shader_parameter("rgb_texture", rgb_texture)
					shader_material.set_shader_parameter("mode", 0)
					s2 = rgb_texture.get_size()
				CameraFeed.FeedDataType.FEED_YCBCR_SEP:
					y_texture.camera_feed_id = id
					cbcr_texture.camera_feed_id = id
					shader_material.set_shader_parameter("y_texture", y_texture)
					shader_material.set_shader_parameter("cbcr_texture", cbcr_texture)
					shader_material.set_shader_parameter("mode", 1)
					s2 = y_texture.get_size()
				_:
					print("Unknown datatype: %s" % dt)
					return
			var image2 := Image.create(int(s2.x), int(s2.y), false, Image.FORMAT_RGBA8)
			image2.fill(Color.WHITE)
			texture = ImageTexture.create_from_image(image2)
			camera_view.texture = texture
		if OS.get_name() == "macOS":
			feed.format_changed.connect(_on_frame_changed.call_deferred, ConnectFlags.CONNECT_ONE_SHOT)
		else:
			feed.frame_changed.connect(_on_frame_changed.call_deferred, ConnectFlags.CONNECT_ONE_SHOT)
		feed.feed_is_active = true
	else:
		print("Error: ShaderMaterial is not initialized.")
		feed.feed_is_active = false
