extends CharacterBody3D

# --- Settings ---
@export_group("Movement")
@export var WALK_SPEED = 5.0
@export var SPRINT_SPEED = 8.0
@export var CROUCH_SPEED = 2.5
@export var JUMP_VELOCITY = 4.5
@export var ACCEL = 10.0
@export var FRICTION = 8.0

@export_group("Feel")
@export var MOUSE_SENS = 0.002
@export var CROUCH_LERP_SPEED = 10.0

@export_group("Headbob")
@export var BOB_FREQ = 2.4
@export var BOB_AMP = 0.08

# --- Nodes ---
@export var neck: Node3D
@export var camera: Camera3D
@export var mesh: MeshInstance3D
@export var collision: CollisionShape3D
@export var crouch_ray: RayCast3D # Used to check if we can stand up

# --- State ---
var is_crouching = false
var current_speed = 5.0
var t_bob = 0.0

func _ready() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
    if neck == null:
        return
        
    # Toggle mouse visibility when Escape is pressed
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        else:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

    # Only process mouse look if the mouse is captured
    if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        # Mouse Look
        if event is InputEventMouseMotion:
            rotate_y(-event.relative.x * MOUSE_SENS)
            neck.rotate_x(-event.relative.y * MOUSE_SENS)
            neck.rotation.x = clamp(neck.rotation.x, deg_to_rad(-80), deg_to_rad(80))

func _physics_process(delta: float) -> void:
    # Make sure our nodes are assigned
    if neck == null or camera == null or mesh == null or collision == null or crouch_ray == null:
        return

    # 1. Handle Crouch Toggle & Un-Crouch Logic
    if Input.is_action_just_pressed("Crouch"):
        if is_crouching:
            # Only stand up if nothing is above us
            if not crouch_ray.is_colliding():
                is_crouching = false
        else:
            is_crouching = true

    # 2. Smooth Crouch Transition (Lerp)
    var target_scale = 0.5 if is_crouching else 1.0
    var target_neck_pos = 0.0 if is_crouching else 0.5 # Lower camera when crouching

    mesh.scale.y = lerp(mesh.scale.y, target_scale, delta * CROUCH_LERP_SPEED)
    
    # Update CollisionShape3D height directly instead of scaling it (Godot Jolt Physics requirement)
    if collision.shape is CapsuleShape3D:
        var target_height = 1.0 if is_crouching else 2.0 # Assuming default capsule height is 2.0
        collision.shape.height = lerp(collision.shape.height, target_height, delta * CROUCH_LERP_SPEED)
        # Shift collision center so it stays grounded
        collision.position.y = lerp(collision.position.y, target_height / 2.0 - 1.0, delta * CROUCH_LERP_SPEED)

    neck.position.y = lerp(neck.position.y, target_neck_pos, delta * CROUCH_LERP_SPEED)

    # 3. Gravity
    if not is_on_floor():
        velocity += get_gravity() * delta

    # 4. Handle Jump
    if Input.is_action_just_pressed("Jump") and is_on_floor() and not is_crouching:
        velocity.y = JUMP_VELOCITY

    # 5. Handle Sprinting
    if Input.is_action_pressed("Sprint") and not is_crouching:
        current_speed = SPRINT_SPEED
    elif is_crouching:
        current_speed = CROUCH_SPEED
    else:
        current_speed = WALK_SPEED

    # 6. Movement Logic (Acceleration / Friction)
    var input_dir = Input.get_vector("MoveLeft", "MoveRight", "MoveForward", "MoveBackwards")
    var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
    
    if direction:
        velocity.x = lerp(velocity.x, direction.x * current_speed, delta * ACCEL)
        velocity.z = lerp(velocity.z, direction.z * current_speed, delta * ACCEL)
    else:
        velocity.x = lerp(velocity.x, 0.0, delta * FRICTION)
        velocity.z = lerp(velocity.z, 0.0, delta * FRICTION)

    move_and_slide()

    # 7. Headbob
    t_bob += delta * velocity.length() * float(is_on_floor())
    var target_cam_pos = Vector3.ZERO
    
    # Only bob if moving on the floor
    if is_on_floor() and velocity.length() > 0.5:
        target_cam_pos = _headbob(t_bob)
    else:
        # Slowly reset headbob when stopped
        target_cam_pos = Vector3.ZERO
        t_bob = 0.0
        
    camera.transform.origin = camera.transform.origin.lerp(target_cam_pos, delta * 10.0)

func _headbob(time: float) -> Vector3:
    var pos = Vector3.ZERO
    # Sine wave for vertical bobbing (up/down)
    pos.y = sin(time * BOB_FREQ) * BOB_AMP
    # Cosine wave for horizontal bobbing (left/right) at half the frequency
    pos.x = cos(time * BOB_FREQ / 2.0) * BOB_AMP
    return pos
