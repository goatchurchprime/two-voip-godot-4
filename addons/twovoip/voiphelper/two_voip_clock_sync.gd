class_name TwoVoipClockSync
extends RefCounted


# t1/t4 use the initiating clock; t2/t3 use the responding clock.
# The returned interval contains responder-minus-initiator without assuming
# equal one-way delays. The midpoint is only the best symmetric-path guess.
static func calculate_exchange(t1_usec: int, t2_usec: int,
		t3_usec: int, t4_usec: int) -> Dictionary:
	if t3_usec < t2_usec or t4_usec < t1_usec:
		return {}
	var offset_lower_usec := t3_usec - t4_usec
	var offset_upper_usec := t2_usec - t1_usec
	if offset_upper_usec < offset_lower_usec:
		return {}
	var round_trip_usec := offset_upper_usec - offset_lower_usec
	return {
		"remote_minus_local_usec": roundi(
				(offset_lower_usec + offset_upper_usec) / 2.0),
		"offset_lower_usec": offset_lower_usec,
		"offset_upper_usec": offset_upper_usec,
		"uncertainty_usec": ceili(round_trip_usec / 2.0),
		"round_trip_usec": round_trip_usec,
	}
