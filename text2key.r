REBOL [
  title: {Text2Key}
  author: {iarwain@orx-project.org}
  date: 24-May-2020
  file: %text2key.r
]

; === Generic backend context ===
backend: context [
  file: extension: none
  result: copy [] buffer: copy [] current: 1
  emit: func [data] [
    repend buffer data
  ]
  save: does [
    write/lines file buffer
  ]
  new: funct [file'] [
    make self [
      replace file: to-rebol-file file' suffix? file extension
    ]
  ]
]

; === AutoHotKey backend context ===
autohotkey: make backend [
  extension: %.ahk
  move: func [delta] [
    emit rejoin [{Send ^{} pick [{Up} {Down}] delta < 0 { } abs delta {^}}]
  ]
  delay: func [duration] [
    emit rejoin [{Sleep } to-integer 1000 * to-decimal duration]
  ]
  copy: func [source target count] [
    ; TODO
  ]
  insert: func [lines /local carry text] [
    if carry: to-logic all [current < length? result not empty? lines not empty? result/:current] [
      emit {SendEvent {Text}`n}
      emit {Send {Up}}
    ]
    forall lines [
      text: replace/all system/words/copy lines/1 {;} {`;}
      if any [not carry not last? lines] [
        append text {`n}
      ]
      emit rejoin [{SendEvent {Text}} text]
    ]
    if carry [
      emit {Send {Right}}
    ]
  ]
  remove: func [count] [
    emit rejoin [{Send {Shift Down}^{Down } count {^}{Shift Up}{Delete}}]
  ]
  rate: func [value] [
    value: load value
    emit rejoin [{SetKeyDelay } either value = 0 [0] [to-integer 1000 * 1.0 / value] {, 0}]
  ]
  key: func [value] [
    foreach [src dst] [
      {ctrl}    {^^}
      {alt}     {!}
      {shift}   {+}
      {win}     {#}
      { }       {}
    ] [
      replace/all value src dst
    ]
    emit rejoin [uppercase value {::}]
  ]
]

; === Fetch args ===
if attempt [exists? file: to-file system/options/args/1] [

  echo %text2key.log
  begin: now/precise/time

  ; === Implement backend exporter ===
  exporter: autohotkey/new file

  ; === Parse sections and steps ===
  do funct [] [
    label: [integer! opt ["." integer!]]
    option: [
      #":" [#"<" (action: 'copy) | #">" (action: 'replace) | #"|" (action: 'delay) | #"'" (action: 'rate)] copy target label
    | (action: none target: none)
    ]
    space: charset [#" " #"^-"]
    spaces: [any space]
    comment-marker: [{//} | #";" | #"#"]
    section-marker: [
      spaces comment-marker spaces #"[" copy section label option #"]" thru lf
    ]
    key-marker: [
      spaces comment-marker spaces #"[" {key} #":" copy value to #"]" thru lf (set 'key trim value)
    ]

    set 'sections make hash! []
    current: do add-section: func [
      label target-action target
    ] [
      last append sections reduce [to-string label context compose [action: target-action target: (to-string target) line-count: 0 content: copy []]]
    ] 0 none none

    print [{== Parsing [} to-local-file file {]}]
    parse read file [
      any [
        section-marker (current: add-section section action target)
      | key-marker
      | copy line thru lf (append current/content trim/tail line current/line-count: current/line-count + 1)
      ]
    ]
    set 'steps sort/compare extract sections 2 func [a b] [(load a) < (load b)]
  ]

  ; === Process all steps ===
  either steps = unique steps [
    print [{== Setting key [} key {]}]
    exporter/key key
    print [{== Processing} length? steps {steps}]
    do funct [] [
      find-line: funct [section /with current] [
        result: 1
        foreach [label content] sections [
          case [
            label = section [
              break
            ]
            all [
              not find replaced label
              (load label) < (load either with [current] [section])
            ] [
              result: result + sections/:label/line-count
            ]
          ]
        ]
        result
      ]
      move-to: func [line] [
        if exporter/current != line [
          print [{  . Moving to line} line rejoin [{[} pick [{+} {}] line > exporter/current line - exporter/current {]}]]
          exporter/move line - exporter/current
          exporter/current: line
        ]
      ]
      replaced: copy []
      foreach step steps [
        section: sections/:step
        print [{ - Step [} step {]}]
        switch section/action [
          rate [
            print [{  . Set rate to} section/target {cps}]
            exporter/rate section/target
          ]
          delay [
            print [{  . Delaying} load section/target {seconds}]
            exporter/delay section/target
          ]
          copy [
            target: find-line/with section/target step
            print [{  . Copying from [} section/target {]} sections/(section/target)/line-count {lines at line} target]
          ]
          replace [
            either not find replaced section/target [
              move-to target: find-line/with section/target step
              print [{  . Replacing [} section/target {], removing} sections/(section/target)/line-count {lines at line} target]
              remove/part at exporter/result target sections/(section/target)/line-count
              exporter/remove sections/(section/target)/line-count
              append replaced section/target
            ] [
              print [{!! Aborting: trying to replace [} section/target {] which was already replaced earlier}]
              break
            ]
          ]
        ]
        move-to find-line step
        print [{  . Inserting} section/line-count {lines}]
        insert at exporter/result find-line step section/content
        exporter/insert section/content
        exporter/current: exporter/current + section/line-count
      ]

      ; === Saving
      print [{== Saving [} to-local-file exporter/file {]}]
      exporter/save

      end: now/precise/time
      print [{== [} (end - begin) {] Success!}]
    ]
  ] [
    print [{!! Can't process, duplicated steps found in [} steps {]}]
  ]
]
