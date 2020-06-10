REBOL [
  title: {Text2Key}
  author: {iarwain@orx-project.org}
  date: 24-May-2020
  file: %text2key.r
]

; === Generic backend context ===
backend: context [
  data: copy [] output: copy [] current: 1
  file: extension: none
  emit: func [data] [
    repend output data
  ]
  save: does [
    write/lines file output
  ]
  new: func [file'] [
    make self [
      replace file: to-rebol-file file' suffix? file extension
    ]
  ]
]

; === AutoHotKey backend context ===
autohotkey: make backend [

  ; === Variables ===
  extension: %.ahk remove-count: 0 remove-data: none

  ; === Initialization ===
  emit {Esc::ExitApp}
  emit {^^!F1::Reload}

  ; === Functions ===
  copy: func [source target count] [
    ; TODO
  ]
  delay: func [duration] [
    emit rejoin [{Sleep } to-integer 1000 * to-decimal duration]
  ]
  highlight: func [delta] [
    emit rejoin [{Send {Shift Down}^{} pick [{Down } {Up }] delta > 0 abs delta {^}{Shift Up}}]
  ]
  insert: func [lines /local carry text] [
    either remove-count != 0 [
      foreach line lines [
        either remove-count > 0  [
            emit {Send {Insert}}
            emit rejoin [{SendEvent {Text}} replace/all system/words/copy line {;} {`;}]
            if (length? line) < (length? remove-data/1) [
              emit {Send {Shift Down}{End}{Shift Up}{Delete}}
            ]
            emit {Send {Right}}
            emit {Send {Insert}}
        ] [
          emit rejoin [{SendEvent {Text}} replace/all system/words/copy line {;} {`;} {`n}]
        ]
        remove-count: remove-count - 1
        remove-data: next remove-data
      ]
      if remove-count > 0 [
        emit rejoin [{Send {Shift Down}^{Down } remove-count {^}{Shift Up}{Delete}}]
      ]
      remove-count: 0
    ] [
      if carry: to-logic all [current < length? data not empty? lines not empty? data/:current] [
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
  move: func [delta] [
    if remove-count != 0 [
      emit rejoin [{Send {Shift Down}^{Down } remove-count {^}{Shift Up}{Delete}}]
      remove-count: 0
    ]
    emit rejoin [{Send ^{} pick [{Up} {Down}] delta < 0 { } abs delta {^}}]
  ]
  rate: func [value] [
    value: load value
    emit rejoin [{SetKeyDelay } either value = 0 [0] [to-integer 1000 * 1.0 / value] {, 0}]
  ]
  remove: func [count] [
    remove-count: count
    remove-data: system/words/copy/deep/part at data current count
  ]
  scroll: func [delta] [
    delta: to-integer delta
    emit rejoin [{Send {Control Down}^{} pick [{Down } {Up }] delta > 0 abs delta {^}{Control Up}}]
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
      #":" [#"<" (action: 'copy) | #">" (action: 'replace) | #"|" (action: 'delay) | #"'" (action: 'rate) | #"#" (action: 'highlight) | #"." (action: 'scroll)] copy target label
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

        ; === Pre-actions ===
        switch section/action [
          copy [
            target: find-line/with section/target step
            print [{  . Copying from [} section/target {]} sections/(section/target)/line-count {lines at line} target]
          ]
          delay [
            print [{  . Delaying} load section/target {seconds}]
            exporter/delay section/target
          ]
          rate [
            print [{  . Set rate to} section/target {cps}]
            exporter/rate section/target
          ]
          replace [
            either not find replaced section/target [
              move-to target: find-line/with section/target step
              print [{  . Replacing [} section/target {], removing} sections/(section/target)/line-count {lines at line} target]
              exporter/remove sections/(section/target)/line-count
              remove/part at exporter/data target sections/(section/target)/line-count
              append replaced section/target
            ] [
              print [{!! Aborting: trying to replace [} section/target {] which was already replaced earlier}]
              break
            ]
          ]
        ]

        ; === Insertion ===
        move-to find-line step
        print [{  . Inserting} section/line-count {lines}]
        exporter/insert section/content
        insert at exporter/data find-line step section/content
        exporter/current: exporter/current + section/line-count

        ; === Post-actions ===
        switch section/action [
          highlight [
            print [{  . Highlighting to beginning of [} section/target {]}]
            exporter/highlight (target: find-line/with section/target step) - exporter/current
            exporter/current: target
          ]
          scroll [
            print [{  . Scrolling [} section/target {] lines}]
            exporter/scroll section/target
          ]
        ]
      ]

      ; === Saving
      print [{== Saving [} to-local-file exporter/file {]}]
      exporter/save

      end: now/precise/time
      print [{== [} (end - begin) {] Success!}]
    ]
  ] [
    print [{!! Can't process, found duplicated steps [} unique collect [forall steps [if find next steps steps/1 [keep steps/1]]] {]}]
  ]
]
