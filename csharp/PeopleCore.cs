using Godot;
using System.Collections.Generic;

/// Spike (#422): the flat person data and its hot loops in C#. people.gd forwards to this.
/// Integers only, same layout and same semantics as the GDScript it replaces.
[GlobalClass]
public partial class PeopleCore : RefCounted
{
	public const int FIELDS = 14;
	const int ID = 0, HOME = 1, WORK = 2, OFFSET = 3, GOAL = 4, TRIP = 5, LOCATION = 6, STRESS = 7,
		TRIP_LEFT = 8, TRIP_TOTAL = 9, TRIP_FROM = 10, TRIP_LEG = 11, MOOD = 12, LOW_DAYS = 13;
	const int NONE = -1;
	const int DEST_HOME = 0, DEST_WORK = 1, DEST_BREAK = 2, DEST_LUNCH = 3, DEST_AWAY = 4;
	const int TRIP_IDLE = 0, TRIP_REQUESTED = 1, TRIP_MOVING = 2, TRIP_RIDING = 3;
	const int STRESS_MAX = 300, MOOD_MAX = 100, MOOD_START = 75;
	const int ARRIVE = 540, BREAK = 630, LUNCH = 720, LEAVE = 1020;
	const int RESIDENT_OUT = 480, RESIDENT_BACK = 1080, WEEKEND_OUT = 660, WEEKEND_BACK = 900;
	const int BREAK_LENGTH = 15, LUNCH_LENGTH = 60;

	int[] _d = new int[FIELDS * 64];
	int _n;
	int _nextId;
	int _lastMinute = -1;
	readonly Dictionary<int, int> _index = new();

	public int Count() => _n;

	void Grow()
	{
		if ((_n + 1) * FIELDS > _d.Length) System.Array.Resize(ref _d, _d.Length * 2);
	}

	public int NextId() => _nextId;
	public int LastMinute() => _lastMinute;

	public int AddRow(int home, int work, int offset, int goal, int trip, int start)
	{
		int id = _nextId++;
		Grow();
		_index[id] = _n;
		int b = _n * FIELDS;
		_d[b + ID] = id; _d[b + HOME] = home; _d[b + WORK] = work; _d[b + OFFSET] = offset;
		_d[b + GOAL] = goal; _d[b + TRIP] = trip; _d[b + LOCATION] = start; _d[b + STRESS] = 0;
		_d[b + TRIP_LEFT] = 0; _d[b + TRIP_TOTAL] = 0; _d[b + TRIP_FROM] = NONE; _d[b + TRIP_LEG] = 0;
		_d[b + MOOD] = MOOD_START; _d[b + LOW_DAYS] = 0;
		_n++;
		return id;
	}

	void RebuildIndex()
	{
		_index.Clear();
		for (int i = 0; i < _n; i++) _index.TryAdd(_d[i * FIELDS + ID], i);
	}

	public int RemoveRoom(int room)
	{
		int w = 0, removed = 0;
		for (int i = 0; i < _n; i++)
		{
			int b = i * FIELDS;
			if (_d[b + HOME] == room || _d[b + WORK] == room) { removed++; continue; }
			if (w != i) System.Array.Copy(_d, b, _d, w * FIELDS, FIELDS);
			w++;
		}
		_n = w;
		RebuildIndex();
		return removed;
	}

	public void RemovePerson(int i)
	{
		System.Array.Copy(_d, (i + 1) * FIELDS, _d, i * FIELDS, (_n - i - 1) * FIELDS);
		_n--;
		RebuildIndex();
	}

	public int WorkersIn(int room)
	{
		int n = 0;
		for (int i = 0; i < _n; i++) if (_d[i * FIELDS + WORK] == room) n++;
		return n;
	}

	public Godot.Collections.Dictionary WorkerCounts()
	{
		var counts = new Dictionary<int, int>();
		var order = new List<int>();
		for (int i = 0; i < _n; i++)
		{
			int room = _d[i * FIELDS + WORK];
			if (counts.TryGetValue(room, out int c)) counts[room] = c + 1;
			else { counts[room] = 1; order.Add(room); }
		}
		var result = new Godot.Collections.Dictionary();
		foreach (int room in order) result[room] = counts[room];
		return result;
	}

	public int IndexOf(int id) => _index.TryGetValue(id, out int i) ? i : -1;
	public int IdAt(int i) => _d[i * FIELDS + ID];
	public int HomeOf(int i) => _d[i * FIELDS + HOME];
	public int WorkOf(int i) => _d[i * FIELDS + WORK];
	public int OffsetOf(int i) => _d[i * FIELDS + OFFSET];
	public int GoalOf(int i) => _d[i * FIELDS + GOAL];
	public int TripState(int i) => _d[i * FIELDS + TRIP];
	public int LocationOf(int i) => _d[i * FIELDS + LOCATION];
	public int StressOf(int i) => _d[i * FIELDS + STRESS];
	public int MoodOf(int i) => _d[i * FIELDS + MOOD];
	public int LowDaysOf(int i) => _d[i * FIELDS + LOW_DAYS];
	public int TripLeft(int i) => _d[i * FIELDS + TRIP_LEFT];
	public int TripFrom(int i) => _d[i * FIELDS + TRIP_FROM];
	public int TripTotal(int i) => _d[i * FIELDS + TRIP_TOTAL];
	public int TripLeg(int i) => _d[i * FIELDS + TRIP_LEG];
	public void SetHome(int i, int room) => _d[i * FIELDS + HOME] = room;
	public void SetStress(int i, int v) => _d[i * FIELDS + STRESS] = System.Math.Clamp(v, 0, STRESS_MAX);
	public void SetMood(int i, int v) => _d[i * FIELDS + MOOD] = System.Math.Clamp(v, 0, MOOD_MAX);
	public void SetLowDays(int i, int v) => _d[i * FIELDS + LOW_DAYS] = System.Math.Max(0, v);
	public void AddStress(int i, int a) => SetStress(i, _d[i * FIELDS + STRESS] + a);
	public void RawSet(int i, int field, int value) => _d[i * FIELDS + field] = value;

	public int InTowerCount()
	{
		int n = 0;
		for (int i = 0; i < _n; i++)
		{
			int b = i * FIELDS;
			if (_d[b + LOCATION] != NONE || _d[b + TRIP] != TRIP_IDLE) n++;
		}
		return n;
	}

	public int GoalRoom(int i)
	{
		switch (_d[i * FIELDS + GOAL])
		{
			case DEST_HOME: return _d[i * FIELDS + HOME];
			case DEST_AWAY: return NONE;
		}
		return _d[i * FIELDS + WORK];
	}

	int ScheduledGoal(int b, int day, int minute, int we, Callable guestHome, Dictionary<int, bool> guestCache)
	{
		int goal = DEST_HOME;
		int home = _d[b + HOME];
		if (_d[b + WORK] == NONE)
		{
			if (home != NONE)
			{
				bool guest = false;
				if (!guestHome.Equals(default(Callable)))
				{
					if (!guestCache.TryGetValue(home, out guest))
					{
						guest = guestHome.Call(home).AsBool();
						guestCache[home] = guest;
					}
				}
				if (!guest)
				{
					if (day == we)
					{
						if (WEEKEND_OUT <= minute) goal = DEST_AWAY;
						if (WEEKEND_BACK <= minute) goal = DEST_HOME;
					}
					else
					{
						if (RESIDENT_OUT <= minute) goal = DEST_AWAY;
						if (RESIDENT_BACK <= minute) goal = DEST_HOME;
					}
				}
			}
			return goal;
		}
		if (day == we) return goal;
		if (ARRIVE + _d[b + OFFSET] <= minute) goal = DEST_WORK;
		if (BREAK <= minute) goal = DEST_BREAK;
		if (BREAK + BREAK_LENGTH <= minute) goal = DEST_WORK;
		if (LUNCH <= minute) goal = DEST_LUNCH;
		if (LUNCH + LUNCH_LENGTH <= minute) goal = DEST_WORK;
		if (LEAVE <= minute) goal = DEST_HOME;
		return goal;
	}

	public int ScheduledGoalOf(int i, int day, int minute, int we, Callable guestHome)
		=> ScheduledGoal(i * FIELDS, day, minute, we, guestHome, new Dictionary<int, bool>());

	/// People.tick: the whole per-minute loop in C#. guestHome is called back into GDScript once per distinct room.
	public void Tick(int minute, int day, int we, Callable guestHome)
	{
		if (minute == _lastMinute) return;
		_lastMinute = minute;
		var cache = new Dictionary<int, bool>();
		for (int i = 0; i < _n; i++)
		{
			int b = i * FIELDS;
			if (_d[b + WORK] == NONE && _d[b + HOME] == NONE) continue;
			int goal = ScheduledGoal(b, day, minute, we, guestHome, cache);
			if (goal != _d[b + GOAL]) _d[b + GOAL] = goal;
			int gr = GoalRoom(i);
			if (gr != _d[b + LOCATION] && _d[b + TRIP] == TRIP_IDLE && _d[b + TRIP_LEFT] == 0) _d[b + TRIP] = TRIP_REQUESTED;
		}
	}

	public void StartTrip(int i, int minutes)
	{
		int b = i * FIELDS;
		_d[b + TRIP_FROM] = _d[b + LOCATION];
		_d[b + TRIP] = TRIP_MOVING;
		_d[b + TRIP_LEFT] = minutes;
		_d[b + TRIP_TOTAL] = minutes;
		_d[b + TRIP_LEG] = 0;
		_d[b + LOCATION] = NONE;
	}

	public void SetSegment(int i, int leg, int minutes)
	{
		int b = i * FIELDS;
		_d[b + TRIP] = TRIP_MOVING; _d[b + TRIP_LEG] = leg; _d[b + TRIP_LEFT] = minutes; _d[b + TRIP_TOTAL] = minutes;
	}

	public void SetRiding(int i, int leg)
	{
		int b = i * FIELDS;
		_d[b + TRIP] = TRIP_RIDING; _d[b + TRIP_LEG] = leg; _d[b + TRIP_LEFT] = 0;
	}

	public void FinishTrip(int i)
	{
		int b = i * FIELDS;
		_d[b + TRIP] = TRIP_IDLE; _d[b + TRIP_LEFT] = 0; _d[b + TRIP_TOTAL] = 0; _d[b + TRIP_LEG] = 0;
		_d[b + LOCATION] = GoalRoom(i);
	}

	public int SpendTripMinute(int i)
	{
		int b = i * FIELDS;
		_d[b + TRIP_LEFT] = System.Math.Max(0, _d[b + TRIP_LEFT] - 1);
		return _d[b + TRIP_LEFT];
	}

	public void GiveUpTrip(int i, int cooldown)
	{
		int b = i * FIELDS;
		if (_d[b + TRIP] != TRIP_REQUESTED) _d[b + LOCATION] = _d[b + TRIP_FROM];
		_d[b + TRIP] = TRIP_IDLE; _d[b + TRIP_LEFT] = cooldown; _d[b + TRIP_TOTAL] = 0; _d[b + TRIP_LEG] = 0;
	}

	public void CoolDown(int i) => _d[i * FIELDS + TRIP_LEFT] = System.Math.Max(0, _d[i * FIELDS + TRIP_LEFT] - 1);

	/// The hot loop of Trips.tick: stress and trip minutes for everyone, in index order. A requested trip calls back
	/// into GDScript (route search, elevator queue) at its place in the order, as the GDScript loop did.
	public void TripsLoop(int perWait, int perTravel, int recovery, Callable start)
	{
		int n = _n;
		for (int i = 0; i < n; i++)
		{
			int b = i * FIELDS;
			switch (_d[b + TRIP])
			{
				case TRIP_REQUESTED:
					AddStress(i, perWait);
					start.Call(i);
					break;
				case TRIP_MOVING:
					AddStress(i, perTravel);
					if (SpendTripMinute(i) == 0) FinishTrip(i);
					break;
				case TRIP_RIDING:
					break;
				default:
					CoolDown(i);
					AddStress(i, -recovery);
					break;
			}
		}
	}

	public bool AnyRiding()
	{
		for (int i = 0; i < _n; i++) if (_d[i * FIELDS + TRIP] == TRIP_RIDING) return true;
		return false;
	}

	public int[] RidingIndices()
	{
		var list = new List<int>();
		for (int i = 0; i < _n; i++) if (_d[i * FIELDS + TRIP] == TRIP_RIDING) list.Add(i);
		return list.ToArray();
	}

	public Godot.Collections.Array<int> StateInts()
	{
		var a = new Godot.Collections.Array<int>();
		a.Resize(3 + _n * FIELDS);
		a[0] = _nextId; a[1] = _lastMinute; a[2] = _n;
		for (int k = 0; k < _n * FIELDS; k++) a[3 + k] = _d[k];
		return a;
	}

	public void LoadInts(Godot.Collections.Array ints)
	{
		_nextId = ints[0].AsInt32();
		_lastMinute = ints[1].AsInt32();
		int total = ints.Count - 3;
		_d = new int[System.Math.Max(FIELDS * 64, total + FIELDS * 16)];
		for (int k = 0; k < total; k++) _d[k] = ints[3 + k].AsInt32();
		_n = total / FIELDS;
		RebuildIndex();
	}

	// Interop micro-benchmark helpers (spike only).
	public int Echo(int x) => x;
	int[] _bulk = new int[0];
	public int[] Bulk(int n)
	{
		if (_bulk.Length != n) { _bulk = new int[n]; for (int k = 0; k < n; k++) _bulk[k] = k * 7 % 301; }
		var r = new int[n];
		System.Array.Copy(_bulk, r, n);
		return r;
	}
	public int Sum(Godot.Collections.Array<int> a) { int t = 0; foreach (int v in a) t += v; return t; }
	public int SumPacked(int[] a) { int t = 0; foreach (int v in a) t += v; return t; }
	public int[] BulkStress()
	{
		var r = new int[_n];
		for (int i = 0; i < _n; i++) r[i] = _d[i * FIELDS + STRESS];
		return r;
	}
}
