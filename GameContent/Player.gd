extends KinematicBody2D

var control = false;
# The ID of this player 0,1,2 etc. NOT the network unique ID
var player_id = -1;
var team_id = -1;
var BASE_SPEED = 200;
const SPRINT_SPEED = 50;
const FLAG_SLOWDOWN_SPEED = -25;
var TELEPORT_SPEED = 3000;
var POWERUP_SPEED = 0;
var DASH_COOLDOWN_PMODIFIER = 0;
var player_name = "Guest999";
var speed = BASE_SPEED;
# Where this player starts on the map and should respawn at
var start_pos = Vector2(0,0);
# Whether or not this player is alive
var alive = true;
# Whether or not this player is currently invincible
var invincible = false;
# The camera that is associated with this player. A reference is used because it may switch parents
var camera_ref = null;
# The time in millis the last position was received
var time_of_last_received_pos = 0;
# The position to start lerping from
var lerp_start_pos = Vector2(0,0);
# The position to end lerping at
var lerp_end_pos = Vector2(0,0);
# Whether or not the player is sprinting
var sprintEnabled = false;
# The position the player was in last frame
var last_position = Vector2(0,0);
# The frame of the all of the sprite on the top (Gun, Head, Body)
var look_direction = 0;
# Whether we teleported during this frame
var just_teleported = false;

# Kits / Classes
enum Kits {Bullet, Laser, Demo};
var current_kit = Kits.Bullet;


var Ghost_Trail = preload("res://GameContent/Ghost_Trail.tscn");
var Player_Death = preload("res://GameContent/Player_Death.tscn");


func _ready():
	camera_ref = $Center_Pivot/Camera;
	set_kit(Kits.Bullet);
	
	last_position = position;
	
	if Globals.testing:
		activate_camera();
		control = true
	
	$Respawn_Timer.connect("timeout", self, "_respawn_timer_ended");
	$Invincibility_Timer.connect("timeout", self, "_invincibility_timer_ended");
	$Powerup_Timer.connect("timeout", self, "_powerup_timer_ended");
	lerp_start_pos = position;
	lerp_end_pos = position;

func _input(event):
	if Globals.is_typing_in_chat:
		return;
	if control:
		if event is InputEventKey and event.pressed:
			if event.scancode == KEY_1:
				set_kit(Kits.Bullet);
			if event.scancode == KEY_2:
				set_kit(Kits.Laser);
			if event.scancode == KEY_3:
				set_kit(Kits.Demo);
			if event.scancode == KEY_T:
				get_tree().get_root().get_node("MainScene/NetworkController").rpc("test_ping");
			if event.scancode == KEY_CONTROL:
				if $Flag_Holder.get_child_count() == 0:
					sprintEnabled = !sprintEnabled;
			if event.scancode == KEY_SPACE:
				#Attempt a teleport
				# Re-enable line below to prevent telporting while you have flag
				# if $Flag_Holder.get_child_count() == 0:
				if $Teleport_Timer.time_left == 0 and $Weapon_Node/Laser_Timer.time_left == 0:
					move_on_inputs(true);
					camera_ref.lag_smooth();
					$Teleport_Timer.start();
func _process(delta):
	just_teleported = false;
	var new_speed = get_tree().get_root().get_node("MainScene/NetworkController").get_game_var("playerSpeed");
	if speed == BASE_SPEED:
		speed = new_speed;
	BASE_SPEED = new_speed;
	TELEPORT_SPEED = get_tree().get_root().get_node("MainScene/NetworkController").get_game_var("dashDistance");
	$Teleport_Timer.wait_time = DASH_COOLDOWN_PMODIFIER + float(get_tree().get_root().get_node("MainScene/NetworkController").get_game_var("dashCooldown"))/1000.0;
	
	if control:
		activate_camera();
		# Don't look around if we're shooting a laser
		if $Weapon_Node.current_weapon != $Weapon_Node.Weapons.Laser or $Weapon_Node/Laser_Timer.time_left == 0:
			update_look_direction();
		# Move around as long as we aren't typing in chat
		if !Globals.is_typing_in_chat:
			move_on_inputs();
	
	update();
	
	if $Invincibility_Timer.time_left > 0:
		var t = $Invincibility_Timer.time_left / $Invincibility_Timer.wait_time 
		var x =  (t * 10);
		var color = Color(1,1,1,(sin( (PI / 2) + (x * (1 + (t * ((2 * PI) - 1))))) + 1)/2);
		modulate = color
	
	z_index = global_position.y + 15;
	
	# If we are a puppet and not the server, then lerp our position
	if !Globals.testing and !is_network_master() and !get_tree().is_network_server():
		position = lerp(lerp_start_pos, lerp_end_pos, clamp(float(OS.get_ticks_msec() - time_of_last_received_pos)/float(Globals.player_lerp_time), 0.0, 1.0));
	
	if !Globals.testing and is_network_master() and !get_tree().is_network_server():
		rpc_unreliable_id(1, "send_position", position, player_id);
	
	
	# Animation
	var diff = last_position - position;
	if sqrt(pow(diff.x, 2) + pow(diff.y, 2)) < 1:
		# Idle
		if team_id == 1:
			#$Sprite_Top.set_texture(idle_top_atlas_red);
			pass;
		else:
			#$Sprite_Top.set_texture(idle_top_atlas_blue);
			pass;
		$Sprite_Legs.frame = look_direction;
	else:
		# Moving
		if team_id == 1:
			#$Sprite_Top.set_texture(running_top_atlas_red);
			pass;
		else:
			#$Sprite_Top.set_texture(running_top_atlas_blue);
			pass;
		$Sprite_Legs.frame = look_direction + (int((1-($Leg_Animation_Timer.time_left / $Leg_Animation_Timer.wait_time)) * 4)%4) * $Sprite_Legs.hframes;
	
	
	$Sprite_Head.position.y = int(2 * sin((1 - $Top_Animation_Timer.time_left/$Top_Animation_Timer.wait_time)*(2 * PI)))/2.0;
		
	# Name tag
	var color = "blue";
	if team_id == 1:
		color = "red";
	$Name_Parent/Label_Name.bbcode_text = "[center][color=" + color + "]" + player_name;
	last_position = position;

func set_kit(kit):
	current_kit = kit;
	$Weapon_Node.set_weapon_from_kit(kit);
	var n = "gunner"
	if current_kit == Kits.Bullet:
		n = "gunner";
	elif current_kit == Kits.Laser:
		n = "laser";
	elif current_kit == Kits.Demo:
		n = "demo";

	$Sprite_Head.set_texture(load("res://Assets/Player/" + str(n) + "_head_B.png"));
	$Sprite_Body.set_texture(load("res://Assets/Player/" + str(n) + "_body_B.png"));
	$Sprite_Gun.set_texture(load("res://Assets/Player/" + str(n) + "_gun_B.png"));


func _draw():
	pass;

# Attempts to drop the flag the player is potentially holding. Returns true if there was a flag to drop false otherwise
func attempt_drop_flag() -> bool:
	if $Flag_Holder.get_child_count() == 0:
		return false;
	else: # Otherwise drop our flag
		drop_current_flag($Flag_Holder.get_global_position());
		rpc_id(1, "send_drop_flag", $Flag_Holder.get_global_position());
		return true;

# A vector 2D representing the last movement key directions pressed
var last_movement_input = Vector2(0,0);

# Checks the current pressed keys and calculates a new player position using the KinematicBody2D
func move_on_inputs(teleport = false):
	var input = Vector2(0,0);
	input.x = (1 if Input.is_key_pressed(KEY_D) else 0) - (1 if Input.is_key_pressed(KEY_A) else 0)
	input.y = (1 if Input.is_key_pressed(KEY_S) else 0) - (1 if Input.is_key_pressed(KEY_W) else 0)
	input = input.normalized();
	last_movement_input = input;
	
	
	var move_speed = speed + POWERUP_SPEED;
	if($Flag_Holder.get_child_count() > 0):
		move_speed += FLAG_SLOWDOWN_SPEED;
	if sprintEnabled:
		move_speed += SPRINT_SPEED;
	if teleport:
		move_speed = TELEPORT_SPEED;
		just_teleported = true;
	var vec = (input * move_speed);
	
	var previous_pos = position;
	var change = move_and_slide(vec);
	var new_pos = position;
	
	if teleport:
		if Globals.testing:
			$Teleport_Audio.play();
		else:
			rpc("create_ghost_trail", previous_pos, new_pos);

func enable_powerup(type):
	var text = "";
	if type == 1:
		POWERUP_SPEED = 50;
		$Powerup_Timer.wait_time = 10;
		text = "[color=green]^^ SPEED UP ^^";
	elif type == 2:
		DASH_COOLDOWN_PMODIFIER = -0.5;
		$Powerup_Timer.wait_time = 6;
		text = "[color=blue]˅˅˅˅˅˅^^ DASH RATE UP ^^";
	elif type == 3:
		$Weapon_Node.BULLET_COOLDOWN_PMODIFIER = -0.1;
		$Powerup_Timer.wait_time = 8;
		text = "[color=red]^^ BULLET FIRE RATE UP ^^";
	elif type == 4:
		$Weapon_Node.LASER_WIDTH_PMODIFIER = 15;
		$Powerup_Timer.wait_time = 6;
		text = "[color=#FF8C00]^^ LASER WIDTH UP ^^";
	elif type == 5:
		$Powerup_Timer.wait_time = 10;
		text = "[color=purple]^^ FORCEFIELD RATE UP ^^";
	# Only display message if this is our local player
	if Globals.testing or player_id == Globals.localPlayerID:
		get_tree().get_root().get_node("MainScene/UI_Layer").set_alert_text("[center]" + text);
	$Powerup_Timer.start();

func _powerup_timer_ended():
	POWERUP_SPEED = 0;
	DASH_COOLDOWN_PMODIFIER = 0;
	$Weapon_Node.BULLET_COOLDOWN_PMODIFIER = 0;
	$Weapon_Node.LASER_WIDTH_PMODIFIER = 0;

remotesync func create_ghost_trail(start, end):
	$Teleport_Audio.play();
	for i in range(6):
		var node = Ghost_Trail.instance();
		node.position = start;
		node.position.x = node.position.x + ((i) * (end.x - start.x)/4)
		node.position.y = node.position.y + ((i) * (end.y - start.y)/4)
		node.look_direction = look_direction;
		node.scale = $Sprite_Body.scale
		node.get_node("Sprite_Gun").texture = $Sprite_Gun.texture
		node.get_node("Sprite_Gun").z_index = $Sprite_Gun.z_index
		node.get_node("Sprite_Head").texture = $Sprite_Head.texture
		node.get_node("Sprite_Head").z_index = $Sprite_Head.z_index
		node.get_node("Sprite_Body").texture = $Sprite_Body.texture
		node.get_node("Sprite_Body").z_index = $Sprite_Body.z_index
		node.get_node("Sprite_Legs").texture = $Sprite_Legs.texture
		node.get_node("Sprite_Legs").frame = $Sprite_Legs.frame
		get_tree().get_root().get_node("MainScene").add_child(node);  
		node.get_node("Death_Timer").start((i) * 0.05 + 0.0001);
	# If this is a puppet, use this ghost trail as an oppurtunity to also update its position
	if !is_network_master():
		lerp_start_pos = end;
		lerp_end_pos = end;
		position = end;
	
# Changes the sprite's frame to make it "look" at the mouse
var previous_look_input = Vector2(0,0);
func update_look_direction():
	var pos = get_global_mouse_position();
	var dist = pos - position;
	var angle = get_vector_angle(dist);
	var adjustedAngle = -1 * (angle + (PI/8));
	var octant = (adjustedAngle / (2 * PI)) * 8
	var dir = int((octant + 9) + 4) % 8;
	if dir != look_direction: # If it changed since last time
		set_look_direction(dir);
		if !Globals.testing:
			rpc_unreliable_id(1, "send_look_direction", dir, player_id);


# Gets the angle that a vector is making
func get_vector_angle(dist):
	var angle = (-(PI / 2) if dist.y < 0 else ( 3 * PI / 2)) if dist.x == 0 else atan(dist.y / dist.x);
	angle = angle * -1;
	angle += PI/2;
	if dist.x < 0:
		angle += PI;
	return angle;

# Set the direction that the player is "looking" at by changing sprite frame
func set_look_direction(dir):
	look_direction = dir;
	$Sprite_Head.frame = dir;
	$Sprite_Gun.frame = dir;
	$Sprite_Body.frame = dir;
	$Sprite_Legs.frame = look_direction + (int((1-($Leg_Animation_Timer.time_left / $Leg_Animation_Timer.wait_time)) * 4)%4) * $Sprite_Legs.hframes;
	if dir == 2 or dir == 3:
		$Sprite_Head.z_index =1;
		$Sprite_Body.z_index =0;
		$Sprite_Gun.z_index =2;
	else:
		$Sprite_Head.z_index =2;
		$Sprite_Body.z_index =0;
		$Sprite_Gun.z_index =1;
	

# Updates this player's position with the new given position. Only ever called remotely
func update_position(new_pos):
	# Instantly update position for server
	if get_tree().is_network_server():
		position = new_pos;
		return;
	# Otherwise lerp
	
	position = lerp(lerp_start_pos, lerp_end_pos, clamp(float(OS.get_ticks_msec() - time_of_last_received_pos)/float(Globals.player_lerp_time), 0.0, 1.0));
	time_of_last_received_pos = OS.get_ticks_msec();
	lerp_start_pos = position;
	lerp_end_pos = new_pos;

# Activates the camera on this player
func activate_camera():
	if camera_ref:
		camera_ref.current = true;

# De-activates the camera on this player
func deactivate_camera():
	if camera_ref:
		camera_ref.current = false;

# Called when this player is hit by a projectile
func hit_by_projectile(attacker_id, projectile_type):
	if projectile_type == 0 || projectile_type == 1 || projectile_type == 2 || projectile_type == 3: # Bullet or Laser or Landmine
		die();
		var attacker_team_id = get_tree().get_root().get_node("MainScene/NetworkController").players[attacker_id]["team_id"]
		var attacker_name = get_tree().get_root().get_node("MainScene/NetworkController").players[attacker_id]["name"]
		if attacker_id == Globals.localPlayerID:
			var color = "blue"
			if team_id == 1:
				color = "red";
			get_tree().get_root().get_node("MainScene/UI_Layer").set_alert_text("[center][color=black]KILLED [color=" + color +"]" + player_name);
		if is_network_master():
			get_tree().get_root().get_node("MainScene/UI_Layer").set_big_label_text("KILLED BY\n" + str(attacker_name), attacker_team_id);
			camera_ref.get_parent().remove_child(camera_ref);
			get_tree().get_root().get_node("MainScene/Players/P" + str(attacker_id) + "/Center_Pivot").add_child(camera_ref);
		

# "Kills" the player. Only for visuals on client - the server handles the respawning.
func die():
	visible = false;
	control = false;
	alive = false;
	spawn_death_particles();
	# If we're the server
	if get_tree().is_network_server():
		$Respawn_Timer.start();
	# Drop the flag if you have one
	drop_current_flag($Flag_Holder.get_global_position());
	position = start_pos;
	if is_network_master():
		$Death_Audio.play();
	else:
		$Killed_Audio.play();

func spawn_death_particles():
	var node = Player_Death.instance();
	node.position = position;
	node.xFrame = look_direction;
	node.z_index = z_index;
	get_tree().get_root().get_node("MainScene").add_child(node);

# Called by the respawn timer when it ends
func _respawn_timer_ended():
	rpc("receive_respawn");

# Respawns the player at their team's start location
func respawn():
	visible = true;
	alive = true;
	position = start_pos;
	if is_network_master() and get_tree().get_root().get_node("MainScene/NetworkController").round_is_running:
		control = true;
	start_temporary_invincibility();
	if is_network_master():
		get_tree().get_root().get_node("MainScene/UI_Layer").clear_big_label_text();
		camera_ref.get_parent().remove_child(camera_ref);
		$Center_Pivot.add_child(camera_ref);
	else:
		lerp_start_pos = position;
		lerp_end_pos = position;
		time_of_last_received_pos = 0;

# Takes the given flag
func take_flag(flag_id):
	if Globals.testing or is_network_master():
		get_tree().get_root().get_node("MainScene").speedup_music();
	$Flag_Pickup_Audio.play();
	var flag_team_id;
	for flag in get_tree().get_nodes_in_group("Flags"):
		if flag.flag_id == flag_id:
			flag.re_parent($Flag_Holder);
			flag.is_at_home = false;
			flag.position = Vector2(0,0);
			flag_team_id = flag.team_id;
	sprintEnabled = false;
	var subject = player_name;
	var subjectColor = "blue"
	var color = "red";
	var teamNoun = "RED TEAM";
	if team_id == 1:
		subjectColor = "red";
		color = "blue";
		teamNoun = "BLUE TEAM";
	if player_id == Globals.localPlayerID:
		subject = "You";
	if !Globals.testing and !get_tree().is_network_server():
		if get_tree().get_root().get_node("MainScene/NetworkController").players[Globals.localPlayerID]["team_id"] == flag_team_id:
			teamNoun = "YOUR TEAM";
		get_tree().get_root().get_node("MainScene/UI_Layer").set_alert_text("[center][color=" + subjectColor + "]" + subject + "[color=black] took " + "[color=" + color + "]" + teamNoun + "'s[color=black] flag!");
	

# Drops the currently held flag (If there is one)
func drop_current_flag(flag_position = $Flag_Holder.get_global_position()):
	# Only run if there is a flag in the Flag_Holder
	if $Flag_Holder.get_child_count() > 0:
		if Globals.testing or is_network_master():
			get_tree().get_root().get_node("MainScene").slowdown_music();
		$Flag_Drop_Audio.play();
		# Just get the first flag because there should only ever be one
		var flag = $Flag_Holder.get_children()[0];
		flag.get_node("Area2D").player_id_drop_buffer = player_id;
		flag.get_node("Area2D").ignore_next_buffer_reset = true;
		flag.re_parent(get_tree().get_root().get_node("MainScene"));
		flag.position = flag_position;
		$Weapon_Node/Cooldown_Timer.start();

# Starts the temporary Invincibility cooldown
func start_temporary_invincibility():
	$Invincibility_Timer.start();
	invincible = true;
# Called by timer when invincibility is over
func _invincibility_timer_ended():
	# If we're the server, make the call to actually end invinciblity
	if get_tree().is_network_server():
		rpc("receive_end_invinciblity");



# -------- NETWORKING ------------------------------------------------------------>



# Client tells Server to run this function so that it can send it's latest position
# The Server then sends that position to all other clients
remote func send_position(new_pos, player_id):
	if get_tree().is_network_server(): # Only run if it's the server
		get_tree().get_root().get_node("MainScene/NetworkController").players[player_id]["position"] = position;
		var clients = get_tree().get_network_connected_peers();
		for i in clients: # For each connected client
			if i != get_tree().get_rpc_sender_id(): # Don't do it for the player who sent it
				rpc_unreliable_id(i, "receive_position", new_pos);
		update_position(new_pos); # Also call it locally for the server

# "Receives" the position of this player from the server
remote func receive_position(new_pos):
	update_position(new_pos);

# Client tells the server what direction frame it's looking at 
remote func send_look_direction(frame, player_id):
	if get_tree().is_network_server(): # Only run if it's the server
		var clients = get_tree().get_network_connected_peers();
		for i in clients: # For each connected client
			if i != get_tree().get_rpc_sender_id(): # Don't do it for the player who sent it
				rpc_id(i, "receive_look_direction", frame);
		set_look_direction(frame); # Also call it locally for the server

# "Receives" the direction frame that this player is looking at from the server
remote func receive_look_direction(frame):
	set_look_direction(frame);

# "Receives" notification from the server that this player was hit by a projectile
remotesync func receive_hit(attacker_id, projectile_type):
	hit_by_projectile(attacker_id, projectile_type);

# Receives notification from the server that this player took the given flag
remotesync func receive_take_flag(flag_id):
	take_flag(flag_id);

# Client tells server that it is dropping the flag
remote func send_drop_flag(flag_position):
	if get_tree().is_network_server():# Only run if it's the server
		var clients = get_tree().get_network_connected_peers();
		for i in clients: # For each connected client
			if i != get_tree().get_rpc_sender_id(): # Don't do it for the player who sent it
				rpc_id(i, "receive_drop_flag", flag_position);
		drop_current_flag(flag_position); # Also call it locally for the server

# Sent by server to tell clients that this player dropped its flag at the given position
remote func receive_drop_flag(flag_position):
	drop_current_flag(flag_position);

# Receives notification from the server to respawn this player
remotesync func receive_respawn():
	respawn();

# Received by server to end this player's invincibility
remotesync func receive_end_invinciblity():
	invincible = false;
	$Invincibility_Timer.stop();
	modulate = Color(1,1,1,1);
