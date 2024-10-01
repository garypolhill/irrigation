extensions [ csv ]
globals [
  lake-size ; could be a parameter but just increase n-lakes if you want more water
  p-crop-list
  drought?
  crop-min-size
  crop-inc-size
  crop-header
]

breed [ households household ]
breed [ lakes lake ]
breed [ crops crop ]

households-own [
  energy-need
  land
  store
  memory
]

crops-own [
  water-needs ; per tick
  yield-ok    ; if it gets the water it needs
  yield-less  ; if it gets less water than it needs
  energy      ; per unit yield provided to hh
  planting    ; list 0-11 mod 12 tick of planting time
  growing     ; ticks to grow
  n-missed-irrigation
  crop-type
]

lakes-own [
  volume
  replacement
  surface     ; agentset of patches
]

patches-own [
  patch-type
  part-of-lake
  part-of-household
  nearest-lake
  irrigated?
]

to setup-globals
  set lake-size 3
  set p-crop-list (list p-crop-month-0 p-crop-month-1 p-crop-month-2 p-crop-month-3 p-crop-month-4
    p-crop-month-5 p-crop-month-6 p-crop-month-7 p-crop-month-8 p-crop-month-9 p-crop-month-10 p-crop-month-11)
  set crop-min-size 0.4
  set crop-inc-size 0.1
  set crop-header [ "type" "shape" "color" "water" "yield-ok" "yield-less" "energy" "growing"
    "m0" "m1" "m2" "m3" "m4" "m5" "m6" "m7" "m8" "m9" "m10" "m11"]
end

to setup
  clear-all

  setup-globals

  ask patches [
    set patch-type "none"
    set nearest-lake nobody
    set part-of-lake nobody
    set part-of-household nobody
    set irrigated? false
  ]

  repeat n-lakes [
    create-lakes 1 [
      let centroid one-of patches

      if count patches with [patch-type = "lake"] > 0 [
        set centroid one-of patches with [
          distance nearest-lake > lake-size
        ]
      ]

      move-to centroid
      set surface (patches in-radius lake-size) with [patch-type = "none"]

      set volume lake-volume

      ask surface [
        set pcolor 93 + (6 * ([volume] of myself) / max-lake-volume)
        set part-of-lake myself
        set patch-type "lake"
      ]

      set replacement lake-replacement
      set hidden? true
    ]

    update-nearest-lake
  ]

  create-households n-households [
    set shape "house"
    set color color + 1
    set memory []
    set store hh-en-mult * hh-init-en
    set energy-need hh-en-mult * (hh-en-min + random (hh-en-max - hh-en-min))
    move-to one-of patches with [patch-type = "none"]
    while [not any? neighbors4 with [patch-type = "none"]] [
      move-to one-of patches with [patch-type = "none"]
    ]
    ask patch-here [
      set patch-type "home"
    ]
    set land nobody
    let cur-patch patch-here
    repeat max-holding-size [
      if any? neighbors4 with [patch-type = "none"] [
        move-to one-of neighbors4 with [patch-type = "none"]
        ask patch-here [
          set part-of-household myself
          set patch-type "field"
          set pcolor [color] of myself
        ]
        set land (patch-set land patch-here)
      ]
    ]
    move-to cur-patch
  ]

  ifelse use? [
    load-crops crop-file
  ] [
    create-crops n-crops [
      set hidden? true
      set shape "plant"
      set color color - 3
      set water-needs crop-min-water + random (crop-max-water - crop-min-water)
      set yield-ok yield-ok-min + random (yield-ok-max - yield-ok-min)
      set yield-less yield-less-min + random (yield-less-max - yield-less-min)
      set planting reduce [[so-far next] ->
        ifelse-value random-float 1 < item next p-crop-list [
          lput next so-far
        ] [
          so-far
        ]
      ] fput [] n-values (length p-crop-list) [ i -> i ]
      if length planting = 0 [
        set planting lput random 12 planting
      ]
      set growing 1 + random crop-max-grow-time
      set energy growing * crop-en-per-grow-yield
      set n-missed-irrigation 0
      set crop-type who
    ]
  ]

  ask households [
    ask land [
      choose-initial-crop self myself
    ]
  ]

  set drought? false

  reset-ticks
end

to choose-initial-crop [ field farmer ]
  ask one-of crops with [hidden?] [
    hatch-crops 1 [
      move-to field
      let how-far-along random growing
      set size crop-min-size + crop-inc-size * how-far-along
      set hidden? false
    ]
  ]
end

to update-nearest-lake
  ask patches [
    ifelse patch-type = "lake" [
      set nearest-lake part-of-lake
    ] [
      set nearest-lake [part-of-lake] of one-of (patches with [patch-type = "lake"]) with-min [distance myself]
    ]
  ]
end

to go
  if count households = 0 [
    output-print "All the households have starved!"
    stop
  ]

  ask patches [
    set irrigated? false
  ]
  set drought? (random-float 1 < p-drought)

  ask households [
    plant
  ]

  ask households [
    irrigate
  ]

  ask crops with [not hidden?] [
    grow
  ]

  ask households [
    harvest
  ]

  ask households [
    eat
  ]

  ask lakes [
    if not drought? [
      set volume min (list max-lake-volume (volume + replacement))
    ]
    ask surface [
      set pcolor 93 + (6 * ([volume] of myself) / max-lake-volume)
    ]
  ]

  tick
end

to plant
  ask land with [not any? crops-here] [
    choose-crop self myself
  ]
end

to irrigate
  ask land [
    let water-available [volume] of nearest-lake
    let water-used 0
    ask crops-here [
      ifelse water-needs < water-available and decide-to-irrigate? [
        set water-used water-used + water-needs
      ] [
        set n-missed-irrigation n-missed-irrigation + 1
      ]
    ]
    if water-used > 0 [
      set irrigated? true
      ask nearest-lake [
        set volume volume - water-used
      ]
    ]
  ]
end

to-report decide-to-irrigate?
  report true
end

to grow
  set growing growing - 1
  set size size + crop-inc-size
end

to harvest
  let en 0
  let episodes []
  ask land [
    ask crops-here with [growing = 0 and not hidden?] [
      let d-en 0
      let status "none"
      (ifelse n-missed-irrigation <= n-not-irrigated-ok-yield [
        ; Yield is OK
        set d-en (energy * yield-ok)
        set status "ok"
      ] n-missed-irrigation < n-not-irrigated-no-yield [
        ; Use lower yield option
        set d-en (energy * yield-less)
        set status "less"
      ] [
        set status "fail"
      ])

      set episodes lput (list crop-type n-missed-irrigation d-en status) episodes
      set en en + d-en
      die
    ]
  ]
  set store min (list (hh-max-store * hh-en-mult) (store + en))
  foreach episodes [ episode ->
    set memory lput episode memory
    if length memory > max-memory-size [
      set memory but-first memory
    ]
  ]
end

to eat
  ifelse store >= energy-need [
    set store store - energy-need
  ] [
    ask land [
      ask crops-here [
        die
      ]
      set pcolor black
      set patch-type "none"
      set part-of-household nobody
    ]
    die
  ]
end

to choose-crop [ field hh ]
  let choice-set crops with [hidden? and member? (ticks mod 12) planting]

  if any? choice-set [
    let choice choose-most-remembered choice-set field hh

    ask choice [
      hatch-crops 1 [
        move-to field
        set size crop-min-size
        set hidden? false
      ]
    ]
  ]
end

to-report choose-randomly [ choice-set field hh ]
  report one-of choice-set
end

to-report choose-most-remembered [ choice-set field hh ]
  if count choice-set = 1 [
    report one-of choice-set
  ]

  let selected "NA"
  ask hh [
    let choice-list sort [crop-type] of choice-set
    let memory-count n-values (length choice-list) [ i -> 0 ]
    foreach range length choice-list [ i ->
      let choice item i choice-list

      foreach (filter [ ep -> first ep = choice ] memory) [ ep ->
        set memory-count replace-item i memory-count (1 + item i memory-count)
      ]
    ]
    let max-count max memory-count
    let most []
    foreach range length choice-list [ i ->
      if item i memory-count = max-count [
        set most fput (item i choice-list) most
      ]
    ]
    set selected one-of most
  ]
  if selected = "NA" [
    error "BUG!!"
  ]
  report one-of choice-set with [crop-type = selected]
end

to save-crops [ file-name ]
  if not is-list? crop-header [
    setup-globals
  ]
  let data []
  set data lput crop-header data
  ask crops with [hidden?] [
    let crop-data (list crop-type shape color water-needs yield-ok yield-less energy growing)
    foreach (n-values 12 [ i -> i ]) [ month ->
      set crop-data lput (member? month planting) crop-data
    ]
    set data lput crop-data data
  ]
  csv:to-file file-name data
end

to load-crops [ file-name ]
  if not is-list? crop-header [
    setup-globals
  ]

  if not file-exists? file-name [
    user-message (word "Crop file \"" file-name "\" not found")
    stop
  ]

  let data csv:from-file file-name

  if first data != crop-header [
    user-message (word "File \"" file-name "\" does not look like a crop file from its first line")
    stop
  ]

  ask crops [
    die
  ]

  foreach but-first data [ crop-data ->
    create-crops 1 [
      set hidden? true

      set crop-type item 0 crop-data
      set shape item 1 crop-data
      set color item 2 crop-data
      set water-needs item 3 crop-data
      set yield-ok item 4 crop-data
      set yield-less item 5 crop-data
      set energy item 6 crop-data
      set growing item 7 crop-data

      set planting []
      foreach (n-values 12 [ i -> i ]) [ month ->
        let month-col month + 8
        if (item month-col crop-data) = true [
          set planting lput month planting
        ]
      ]
    ]
  ]
  set n-crops count crops
end
@#$#@#$#@
GRAPHICS-WINDOW
220
11
657
449
-1
-1
13.0
1
10
1
1
1
0
1
1
1
-16
16
-16
16
0
0
1
ticks
30.0

BUTTON
0
10
66
43
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
67
10
122
43
step
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
124
10
179
43
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
0
44
148
77
n-households
n-households
1
100
76.0
1
1
NIL
HORIZONTAL

SLIDER
0
76
148
109
n-lakes
n-lakes
1
10
7.0
1
1
NIL
HORIZONTAL

SLIDER
0
417
218
450
max-holding-size
max-holding-size
1
10
4.0
1
1
NIL
HORIZONTAL

SLIDER
0
109
148
142
n-crops
n-crops
1
5
4.0
1
1
NIL
HORIZONTAL

SLIDER
658
12
830
45
p-crop-month-0
p-crop-month-0
0
1
0.02
0.01
1
NIL
HORIZONTAL

SLIDER
658
45
830
78
p-crop-month-1
p-crop-month-1
0
1
0.02
0.01
1
NIL
HORIZONTAL

SLIDER
658
78
830
111
p-crop-month-2
p-crop-month-2
0
1
0.1
0.01
1
NIL
HORIZONTAL

SLIDER
658
144
830
177
p-crop-month-4
p-crop-month-4
0
1
0.3
0.01
1
NIL
HORIZONTAL

SLIDER
658
177
830
210
p-crop-month-5
p-crop-month-5
0
1
0.35
0.01
1
NIL
HORIZONTAL

SLIDER
658
210
830
243
p-crop-month-6
p-crop-month-6
0
1
0.4
0.01
1
NIL
HORIZONTAL

SLIDER
658
243
830
276
p-crop-month-7
p-crop-month-7
0
1
0.25
0.01
1
NIL
HORIZONTAL

SLIDER
658
276
830
309
p-crop-month-8
p-crop-month-8
0
1
0.1
0.01
1
NIL
HORIZONTAL

SLIDER
658
309
830
342
p-crop-month-9
p-crop-month-9
0
1
0.05
0.01
1
NIL
HORIZONTAL

SLIDER
658
342
830
375
p-crop-month-10
p-crop-month-10
0
1
0.02
0.01
1
NIL
HORIZONTAL

SLIDER
658
111
830
144
p-crop-month-3
p-crop-month-3
0
1
0.2
0.01
1
NIL
HORIZONTAL

SLIDER
658
375
830
408
p-crop-month-11
p-crop-month-11
0
1
0.01
0.01
1
NIL
HORIZONTAL

SLIDER
831
12
1018
45
crop-max-grow-time
crop-max-grow-time
1
12
6.0
1
1
NIL
HORIZONTAL

SLIDER
831
45
1018
78
crop-en-per-grow-yield
crop-en-per-grow-yield
1
100
90.0
1
1
NIL
HORIZONTAL

SLIDER
831
78
1018
111
crop-min-water
crop-min-water
1
10
5.0
1
1
NIL
HORIZONTAL

SLIDER
831
111
1018
144
crop-max-water
crop-max-water
1
20
15.0
1
1
NIL
HORIZONTAL

SLIDER
832
375
947
408
p-drought
p-drought
0
1
0.1
0.01
1
NIL
HORIZONTAL

MONITOR
948
375
1018
420
NIL
drought?
17
1
11

SLIDER
831
144
1018
177
yield-ok-min
yield-ok-min
1
100
70.0
1
1
NIL
HORIZONTAL

SLIDER
831
177
1018
210
yield-ok-max
yield-ok-max
1
100
80.0
1
1
NIL
HORIZONTAL

SLIDER
831
210
1018
243
yield-less-min
yield-less-min
0
100
30.0
1
1
NIL
HORIZONTAL

SLIDER
831
243
1018
276
yield-less-max
yield-less-max
1
100
50.0
1
1
NIL
HORIZONTAL

SLIDER
831
276
1018
309
n-not-irrigated-no-yield
n-not-irrigated-no-yield
0
12
4.0
1
1
NIL
HORIZONTAL

SLIDER
831
309
1018
342
n-not-irrigated-ok-yield
n-not-irrigated-ok-yield
0
12
1.0
1
1
NIL
HORIZONTAL

SLIDER
0
217
127
250
hh-en-min
hh-en-min
0
100
10.0
1
1
NIL
HORIZONTAL

SLIDER
1
250
218
283
hh-en-max
hh-en-max
0
100
20.0
1
1
NIL
HORIZONTAL

SLIDER
1
284
218
317
hh-en-mult
hh-en-mult
0
10000
1000.0
100
1
NIL
HORIZONTAL

SLIDER
1
351
218
384
hh-init-en
hh-init-en
0
100
100.0
1
1
NIL
HORIZONTAL

SLIDER
658
418
830
451
lake-volume
lake-volume
100
10000
1200.0
100
1
NIL
HORIZONTAL

SLIDER
832
418
1018
451
lake-replacement
lake-replacement
0
1000
50.0
10
1
NIL
HORIZONTAL

PLOT
6
574
358
694
household stores
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"median" 1.0 0 -16777216 true "" "if count households > 0 [plot median [store] of households]"
"max" 1.0 0 -7500403 true "" "if count households > 0 [plot max [store] of households]"
"min" 1.0 0 -7500403 true "" "if count households > 0 [plot min [store] of households]"

PLOT
696
574
1018
694
lake volumes
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"median" 1.0 0 -16777216 true "" "plot median [volume] of lakes"
"max" 1.0 0 -7500403 true "" "plot max [volume] of lakes"
"min" 1.0 0 -7500403 true "" "plot min [volume] of lakes"

PLOT
509
453
1018
573
irrigated crops
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"OK" 1.0 0 -12087248 true "" "plot count crops with [not hidden? and n-missed-irrigation <= n-not-irrigated-ok-yield]"
"less" 1.0 0 -4079321 true "" "plot count crops with [not hidden? and n-missed-irrigation > n-not-irrigated-ok-yield and n-missed-irrigation < n-not-irrigated-no-yield]"
"failed" 1.0 0 -8431303 true "" "plot count crops with [not hidden? and n-missed-irrigation >= n-not-irrigated-no-yield]"

SLIDER
0
384
218
417
max-memory-size
max-memory-size
0
1000
230.0
10
1
NIL
HORIZONTAL

PLOT
359
574
695
694
household knowledge
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"median" 1.0 0 -16777216 true "" "if count households > 0 [ plot median [length memory] of households ]"
"max" 1.0 0 -7500403 true "" "if count households > 0 [ plot max [length memory] of households ]"
"min" 1.0 0 -7500403 true "" "if count households > 0 [ plot min [length memory] of households ]"

PLOT
6
453
507
573
crop usage
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"ask crops with [hidden?] [\n  create-temporary-plot-pen (word crop-type)\n  set-current-plot-pen (word crop-type)\n  set-plot-pen-color color\n]" "ask crops with [hidden?] [\n  set-current-plot-pen (word crop-type)\n  plot count crops with [not hidden? and crop-type = [crop-type] of myself]\n]"
PENS

SLIDER
831
343
1018
376
max-lake-volume
max-lake-volume
100
10000
1500.0
100
1
NIL
HORIZONTAL

SLIDER
1
318
218
351
hh-max-store
hh-max-store
10
1000
500.0
10
1
NIL
HORIZONTAL

INPUTBOX
0
142
218
202
crop-file
crop-file.csv
1
0
String

BUTTON
155
109
218
142
choose
set crop-file user-file\n
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
155
76
218
109
save
if length crop-file = 0 [\n  set crop-file user-new-file\n]\nsave-crops crop-file
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
128
202
218
235
use?
use?
0
1
-1000

TEXTBOX
167
52
217
79
crop-file buttons
9
0.0
1

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
