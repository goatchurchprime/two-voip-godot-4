extends Control


# Called when the node enters the scene tree for the first time.
func _ready():
	var a = [ ]
	for i in range(50):
		a.append(Vector2(i/50.0, (sin(i)+1)/2))
	$Line2D.points = PackedVector2Array(a)

var x = [ ]
var Mx = 0
func addwindow(v):
	x.append(Vector2(len(x)/50.0, 1-v))
	if v > Mx:
		Mx = v
	if len(x) == 50:
		$Line2D.points = PackedVector2Array(x)
		x = [ ]
		print("Mx ", Mx)
		Mx = 0
