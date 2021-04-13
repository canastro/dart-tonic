part of tonic;

/// A Fretting is a map of fingers to sets of frets, that voice a chord on a fretted
/// instrument.
///
/// These are "frettings" and not "voicings" because they also include barre
/// information.
class Fretting {
  final Chord chord;
  final List<FretPosition> positions; // sorted by string index
  final FrettedInstrument instrument;

  // caches:
  List<int?>? _stringFretList;
  String? _fretString;

  Fretting({
    required this.instrument,
    required this.chord,
    required Iterable<FretPosition> positions,
  }) : this.positions = List<FretPosition>.from(sortedBy(
            positions, (FretPosition pos) => pos.stringIndex,
            reverse: true)) {
    assert(positions.length ==
        positions.map((position) => position.stringIndex).toSet().length);
  }

  static Fretting fromFretString(String fretString,
      {required FrettedInstrument instrument, required Chord chord}) {
    if (fretString.length != instrument.stringIndices.length) {
      throw new FormatException(
          "fretString wrong length for $instrument: $fretString");
    }

    final Iterable<String> _fretString = fretString.split('');
    final Iterable<int> _stringIndices = instrument.stringIndices;

    final _positions = IterableZip([_fretString, _stringIndices]);

    final List<FretPosition> positions = _positions
        .map((item) {
          final String char = item[0] as String;
          final int stringIndex = item[1] as int;
          if (char == 'x') return null;
          final fretNumber = char.runes.first - 48;
          if (!(0 <= fretNumber && fretNumber <= 9)) {
            throw new FormatException(
                "Invalid character $char in fretString $fretString");
          }
          final semitones = instrument
              .pitchAt(stringIndex: stringIndex, fretNumber: fretNumber)
              .semitones;
          return new FretPosition(
              stringIndex: stringIndex,
              fretNumber: fretNumber,
              semitones: semitones);
        })
        .whereType<FretPosition>()
        .toList();

    return new Fretting(
        instrument: instrument, chord: chord, positions: positions);
  }

  String toString() => fretString;

  List<int?> get stringFretList => _stringFretList != null
      ? _stringFretList!
      : _stringFretList = instrument.stringIndices
          .map(
            (int stringIndex) => positions.firstWhereOrNull(
              (pos) => pos.stringIndex == stringIndex,
            ),
          )
          .map((FretPosition? pos) => pos == null ? null : pos.fretNumber)
          .toList();

  String get fretString => _fretString != null
      ? _fretString!
      : _fretString = stringFretList
          .map((int? fretNumber) => fretNumber == null
              ? 'x'
              : fretNumber < 10
                  ? fretNumber
                  : throw new UnimplementedError("fret >= 10"))
          .join();

  Iterable<Interval> get intervals => positions
      .map((pos) => new Interval.fromSemitones(
          (pos.semitones - chord.root.semitones) % 12))
      .toList();

  int get inversionIndex => [1, 3, 5, 7, 9].indexOf(intervals.first.number);
}

//
// Barres
//

// powerset = (array) ->
//   return [[]] unless array.length
//   [x, xs...] = array
//   tail = powerset(xs)
//   return tail.concat([x].concat(ys) for ys in tail)

// Returns an array of strings indexed by fret number. Each string
// has a character at each string position:
// '=' = fretted at this fret
// '>' = fretted at a higher fret
// '<' = fretted at a lower fret, or open
// 'x' = muted
// computeBarreCandidateStrings = (instrument, fretArray) ->
//   codeStrings = []
//   for referenceFret in fretArray
//     continue unless typeof(referenceFret) == 'number'
//     codeStrings[referenceFret] or= (for fret in fretArray
//       if fret < referenceFret
//         '<'
//       else if fret > referenceFret
//         '>'
//       else if fret == referenceFret
//         '='
//       else
//         'x').join('')
//   return codeStrings

// findBarres = (instrument, fretArray) ->
//   barres = []
//   for codeString, fret in computeBarreCandidateStrings(instrument, fretArray)
//     continue if fret == 0
//     continue unless codeString
//     match = codeString.match(/(=[>=]+)/)
//     continue unless match
//     run = match[1]
//     continue unless run.match(/\=/g).length > 1
//     barres.push
//       fret: fret
//       firstString: match.index
//       stringCount: run.length
//       fingerReplacementCount: run.match(/\=/g).length
//   return barres

// collectBarreSets = (instrument, fretArray) ->
//   barres = findBarres(instrument, fretArray)
//   return powerset(barres)

/// A FretPosition represents the a fret on a specific string of a fretted
/// instrument.
class FretPosition {
  final int stringIndex;
  final int fretNumber;
  final int semitones;

  FretPosition({
    required this.stringIndex,
    required this.fretNumber,
    required this.semitones,
  });

  // bool operator ==(FretPosition other) =>
  //     stringIndex == other.stringIndex && fretNumber == other.fretNumber;

  @override
  bool operator ==(dynamic other) {
    final FretPosition typedOther = other;
    return stringIndex == typedOther.stringIndex &&
        fretNumber == typedOther.fretNumber;
  }

  int get hashCode => 37 * stringIndex + fretNumber;
  String toString() => "$stringIndex.$fretNumber($semitones)";
  String get inspect => {
        'string': stringIndex,
        'fret': fretNumber,
        'semitones': semitones
      }.toString();
}

Set<FretPosition> chordFrets(
    Chord chord, FrettedInstrument instrument, int highestFret) {
  final positions = new Set<FretPosition>();
  final semitoneSet =
      chord.pitches.map((pitch) => pitch.semitones % 12).toSet();
  eachWithIndex(instrument.stringPitches, (Pitch pitch, int stringIndex) {
    for (var fretNumber = 0; fretNumber <= highestFret; fretNumber++) {
      final semitones = instrument
          .pitchAt(stringIndex: stringIndex, fretNumber: fretNumber)
          .semitones;
      if (semitoneSet.contains(semitones % 12)) {
        final position = new FretPosition(
            stringIndex: stringIndex,
            fretNumber: fretNumber,
            semitones: semitones);
        positions.add(position);
      }
    }
  });
  return positions;
}

List<Fretting> chordFrettings(Chord chord, FrettedInstrument instrument,
    {highestFret: 4}) {
  final int minPitchClasses = chord.intervals.length;
  Map<int, Set<FretPosition>> partitionFretsByString() {
    final Set<FretPosition> positions =
        chordFrets(chord, instrument, highestFret);
    final Map<int, Set<FretPosition>> partitions = new Map.fromIterable(
        instrument.stringIndices,
        key: (index) => index,
        value: (_) => new Set<FretPosition>());
    for (final position in positions) {
      partitions[position.stringIndex]!.add(position);
    }
    return partitions;
  }

  // collectFrettingPositions(fretCandidatesPerString) {
  //   final stringCount = fretCandidatesPerString.length;
  //   final positionSet = [];
  //   final fretArray = [];
  //   void fill(s) {
  //     if (s == stringCount) {
  //       positionSet.push fretArray.slice()
  //     } else {
  //       for fret in fretCandidatesPerString[s]
  //         fretArray[s] = fret
  //         fill s + 1;
  //     }
  //   }
  //   fill(0);
  //   return positionSet;
  // }

  // // actually tests pitch classes, not pitches
  // containsAllChordPitches(fretArray) {
  //   final trace = fretArray.join('') == '022100'
  //   final pitchClasses = []
  //   for fret, string in fretArray
  //     continue unless typeof(fret) is 'number'
  //     pitchClass = instrument.pitchAt({fret, string}).toPitchClass().semitones
  //     pitchClasses.push pitchClass unless pitchClass in pitchClasses
  //   return pitchClasses.length == chord.pitches.length
  // }

  // maximumFretDistance(fretArray) {
  //   frets = (fret for fret in fretArray when typeof(fret) is 'number')
  //   // fretArray = (fret for fret in fretArray when fret > 0)
  //   return Math.max(frets...) - Math.min(frets...) <= 3
  // }

  Set<Fretting> generateFrettings() {
    final frettings = new Set<Fretting>();
    final stringFrets = partitionFretsByString();

    void collect(Iterable<int> unprocessedStringIndices,
        Set<FretPosition> collectedPositions) {
      if (unprocessedStringIndices.isEmpty) {
        final int pitchClassCount = collectedPositions
            .map((position) => position.semitones % 12)
            .toSet()
            .length;
        if (pitchClassCount >= minPitchClasses) {
          frettings.add(new Fretting(
              chord: chord,
              instrument: instrument,
              positions: collectedPositions));
        }
      } else {
        final int stringIndex = unprocessedStringIndices.first;
        final Iterable<int> futureStringIndices =
            unprocessedStringIndices.skip(1);
        collect(futureStringIndices, collectedPositions);
        for (final position in stringFrets[stringIndex]!) {
          final Set<FretPosition> clone = new Set.from(collectedPositions);
          clone.add(position);
          collect(futureStringIndices, clone);
        }
      }
    }

    collect(instrument.stringIndices, new Set<FretPosition>());

    //   final fretArrays = collectFrettingPositions(fretsPerString());
    //   fretArrays = fretArrays.filter(containsAllChordPitches);
    //   fretArrays = fretArrays.filter(maximumFretDistance);
    //   for fretArray in fretArrays
    //     positions = ({fret, string} for fret, string in fretArray when typeof(fret) is 'number')
    //     for pos in positions
    //       pos.intervalClass = Interval.between(chord.root, instrument.pitchAt(pos))
    //       pos.degreeIndex = chord.intervals.indexOf(pos.intervalClass)
    //     sets = [[]]
    //     sets = collectBarreSets(instrument, fretArray) if positions.length > 4
    //     for barres in sets
    //       frettings.push new Fretting {positions, chord, barres, instrument}
    return frettings;
  }

  // final chordNoteCount = chord.pitches.length;

  //
  // Filters
  //

  // // really counts distinct pitch classes, not distinct pitches
  // countDistinctNotes(fingering) {
  //   // _.chain(fingering.positions).pluck('intervalClass').uniq().value().length
  //   final intervalClasses = []
  //   for {intervalClass} in fingering.positions
  //     intervalClasses.push intervalClass unless intervalClass in intervalClasses
  //   return intervalClasses.length;
  // }

  // hasAllNotes(fingering) =>
  //   countDistinctNotes(fingering) == chordNoteCount;

  // mutedMedialStrings(fingering) =>
  //   fingering.fretstring.match(/\dx+\d/);

  // mutedTrebleStrings(fingering) =>
  //   fingering.fretstring.match(/x$/);

  // getFingerCount(fingering) {
  //   final n = (pos for pos in fingering.positions when pos.fret > 0).length;
  //   n -= barre.fingerReplacementCount - 1 for barre in fingering.barres;
  //   return n;
  // }

  // fourFingersOrFewer(fingering) =>
  //   getFingerCount(fingering) <= 4;

  // // Construct the filter set

  // final filters = [];
  // // filters.push name: 'has all chord notes', select: hasAllNotes

  // if (options.filter) {
  //   filters.push name: 'four fingers or fewer', select: fourFingersOrFewer
  // }

  // if (!options.fingerpicking) {
  //   filters.push name: 'no muted medial strings', reject: mutedMedialStrings
  //   filters.push name: 'no muted treble strings', reject: mutedTrebleStrings
  // }

  // // filter by all the filters in the list, except ignore those that wouldn't pass anything
  // filterFrettings(frettings) {
  //   for {name, select, reject} in filters
  //     filtered = frettings
  //     select = ((x) -> not reject(x)) if reject
  //     filtered = filtered.filter(select) if select
  //     unless filtered.length
  //       console.warn "#{chord.name}: no frettings pass filter \"#{name}\"" if warn
  //       filtered = frettings
  //     frettings = filtered
  //   return frettings;
  // }

  //
  // Sort
  //

  // // FIXME count pitch classes, not sounded strings
  // highNoteCount(fingering) =>
  //   fingering.positions.length;

  // isRootPosition(fingering) =>
  //   _(fingering.positions).sortBy((pos) -> pos.string)[0].degreeIndex == 0;

  // reverseSortKey = (fn) -> (a) -> -fn(a)

  // // ordered list of preferences, from most to least important
  // final preferences = [
  //   {name: 'root position', key: isRootPosition}
  //   {name: 'high note count', key: highNoteCount}
  //   {name: 'avoid barres', key: reverseSortKey((fingering) -> fingering.barres.length)}
  //   {name: 'low finger count', key: reverseSortKey(getFingerCount)}
  // ];

  int Function(T, T) compareBy<T>(int Function(T) f, {bool reverse: false}) =>
      reverse ? (a, b) => f(a) - f(b) : (a, b) => f(b) - f(a);

  List<Fretting> sortFrettings(Iterable<Fretting> frettingSet) {
    final List<Fretting> frettingList = frettingSet.toList();

    // number of open strings:
    insertionSort<Fretting>(frettingList,
        compare: compareBy<Fretting>((Fretting f) =>
            f.positions.where((pos) => pos.fretNumber == 0).length));
    // number of sounded strings:
    insertionSort(frettingList,
        compare: compareBy<Fretting>((f) => f.positions.length));
    // root position:
    insertionSort(frettingList,
        compare: compareBy<Fretting>((f) => f.inversionIndex, reverse: true));
    return frettingList;
  }

  //
  // Generate, filter, and sort
  //

  final frettings = generateFrettings();
  // frettings = filterFrettings(frettings);
  final orderedFrettings = sortFrettings(frettings);

  // final properties = {
  //   'root': isRootPosition
  //   'barres': (f) -> f.barres.length
  //   'fingers': getFingerCount
  //   'inversion': (f) -> f.inversionLetter or ''
  //   // 'bass': /^\d{3}x*$/
  //   // 'treble': /^x*\d{3}$/
  //   'skipping': /\dx+\d/
  //   'muting': /\dx/
  //   'open': /0/
  //   'triad': ({positions}) -> positions.length == 3
  //   'position': ({positions}) -> Math.max(_.min(_.pluck(positions, 'fret')) - 1, 0)
  //   'strings': ({positions}) -> positions.length
  // };

  // for name, fn of properties
  //   for fingering in orderedFrettings
  //     value = if fn instanceof RegExp then fn.test(fingering.fretstring) else fn(fingering)
  //     fingering.properties[name] = value

  return orderedFrettings;
}

Fretting bestFrettingFor(Chord chord, FrettedInstrument instrument) =>
    chordFrettings(chord, instrument)[0];
