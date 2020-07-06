REBOL [
  title: {Text2Key}
  author: {iarwain@orx-project.org}
  date: 24-May-2020
  file: %text2key.r
]

; === Default settings ===
key:    {ctrl alt f12}

; === Generic backend context ===
backend: context [
  data: copy [] output: copy [] current: 1
  file: extension: none
  emit: func [data] [
    repend output data
  ]
  export: does [
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
  extension: %.ahk remove-count: highlight-count: 0 remove-data: none

  ; === Initialization ===
  emit {Esc::ExitApp}
  emit {S(text)
{
  if %A_KeyDelay% = 0
  {
    SendEvent {Text}%text%
  }
  else
  {
    Loop, parse, text
    {
      SendEvent {text}%A_LoopField%
      Random delay, 0, %KeyVariation%
      Sleep %delay%
    }
  }
}}

  ; === Functions ===
  copy: func [source target count] [
    ; TODO
  ]
  pause: func [duration] [
    emit rejoin [{Sleep } to-integer 1000 * to-decimal duration]
  ]
  highlight: func [delta] [
    if highlight-count != 0 [
      emit either highlight-count > 0 [{SendEvent {Left}}] [{SendEvent {Right}}]
      highlight-count: 0
    ]
    if remove-count != 0 [
      emit rejoin [{SendEvent {Shift Down}^{Down } remove-count {^}{Shift Up}{Delete}}]
      remove-count: 0
    ]
    emit rejoin [{SendEvent {Shift Down}^{} pick [{Down } {Up }] delta > 0 abs delta {^}{Shift Up}}]
    highlight-count: delta
  ]
  insert: func [lines /local carry text] [
    if highlight-count != 0 [
      emit either highlight-count > 0 [{SendEvent {Left}}] [{SendEvent {Right}}]
      highlight-count: 0
    ]
    either remove-count != 0 [
      foreach line lines [
        either remove-count > 0  [
          emit {SetKeyDelay %A_KeyDelay%, 100}
          emit {SendEvent {Insert}}
          emit {SetKeyDelay %A_KeyDelay%, 0}
          emit rejoin [{S("} replace/all replace/all system/words/copy line {;} {`;} {"} {""} {")}]
          if (length? line) < (length? remove-data/1) [
            emit {SendEvent {Shift Down}{End}{Shift Up}{Delete}}
          ]
          emit {SendEvent {Right}}
          emit {SetKeyDelay %A_KeyDelay%, 100}
          emit {SendEvent {Insert}}
          emit {SetKeyDelay %A_KeyDelay%, 0}
          remove-count: remove-count - 1
          remove-data: next remove-data
        ] [
          emit rejoin [{S("} replace/all replace/all system/words/copy line {;} {`;} {"} {""} {`n} {")}]
        ]
      ]
      if remove-count > 0 [
        emit rejoin [{SendEvent {Shift Down}^{Down } remove-count {^}{Shift Up}{Delete}}]
        remove-count: 0
      ]
    ] [
      if carry: to-logic all [current < length? data not empty? lines not empty? data/:current] [
        emit {SendEvent {Text}`n}
        emit {SendEvent {Up}}
      ]
      forall lines [
        text: replace/all replace/all system/words/copy lines/1 {;} {`;} {"} {""}
        if any [not carry not last? lines] [
          append text {`n}
        ]
        emit rejoin [{S("} text {")}]
      ]
      if carry [
        emit {SendEvent {Right}}
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
    if highlight-count != 0 [
      emit either highlight-count > 0 [{SendEvent {Left}}] [{SendEvent {Right}}]
      highlight-count: 0
    ]
    if remove-count != 0 [
      emit rejoin [{SendEvent {Shift Down}^{Down } remove-count {^}{Shift Up}{Delete}}]
      remove-count: 0
    ]
    emit rejoin [{SendEvent ^{} pick [{Up} {Down}] delta < 0 { } abs delta {^}}]
  ]
  rate: func [values] [
    emit rejoin [{SetKeyDelay } either values/1 = 0 [0] [to-integer 1000 * 1.0 / values/1] {, 0}]
    either 1 < length? values [
      emit reform [{global KeyVariation :=} to-integer (1000 * values/2)]
    ] [
      emit {global KeyVariation := 0}
    ]
  ]
  remove: func [count] [
    remove-count: count
    remove-data: system/words/copy/deep/part at data current count
  ]
  save: does [
    emit {SendEvent {Control Down}{s}{Control Up}}
  ]
  scroll: func [delta] [
    delta: to-integer delta
    emit rejoin [{SendEvent {Control Down}^{} pick [{Down } {Up }] delta > 0 abs delta {^}{Control Up}}]
  ]
  send: func [value] [
    emit {SetKeyDelay %A_KeyDelay%, 100}
    emit reform [either find value #"@" [{ControlSend, ahk_parent,}] [{Send}] replace value #"@" ", ahk_exe "]
    emit {SetKeyDelay %A_KeyDelay%, 0}
  ]
  window: func [value] [
    emit {SetTitleMatchMode, 2}
    emit reform [{WinWait,} replace value #"@" " ahk_exe "]
    emit reform [{WinActivate,} replace value #"@" " ahk_exe "]
  ]
]

; === Log ===
echo %text2key.log

; === Fetch args ===
either attempt [exists? file: to-rebol-file system/options/args/1] [

  begin: now/precise/time

  ; === Implement backend exporter ===
  exporter: autohotkey/new file

  ; === Parse sections and steps ===
  do funct [] [
    label: [spaces opt #"-" integer! opt ["." integer!]]
    option-marker: #":"
    option-value: complement charset reduce [option-marker #"]"]
    option: [
      (action: arg: none) spaces option-marker
      [ #"<"  (action: 'copy)
      | #"#"  (action: 'highlight)
      | #"|"  (action: 'pause)
      | #"'"  (action: 'rate)   spaces copy arg 1 2 label (arg: to-block load arg)
      | #">"  (action: 'replace)
      | #"^^" (action: 'scroll)
      | #"!"  (action: 'save)
      | #"%"  (action: 'send)   spaces copy arg any option-value (arg: trim arg)
      | #"@"  (action: 'window) spaces copy arg any option-value (arg: trim arg)
      | #"."  (action: 'move)
      | #"-"  (actions: post-actions)
      ] opt [copy arg label (arg: load arg)]
    ]
    options: [(actions: pre-actions: copy [] post-actions: copy []) any [option (all [action repend actions [action arg]])]]
    space: charset [#" " #"^-"]
    spaces: [any space]
    comment-rule: [{//} | #";" | #"#"]
    section-rule: [
      spaces comment-rule spaces #"[" (current: none)
      [ copy section label options #"]" (current: add-section section pre-actions post-actions)
      | [ #"]" (section: {})
        | copy section to #"]"
        ] (print [{ - Skipping section} rejoin [{[} section {]}]])
      ] thru lf
    ]
    key-rule: [
      spaces comment-rule spaces #"[" {key} #":" copy value to #"]" thru lf (set 'key trim value)
    ]

    set 'sections make hash! []
    current: 1
    add-section: func [
      label pre-actions' post-actions'
    ] [
      last append sections reduce [trim to-string label context [pre-actions: pre-actions' post-actions: post-actions' line-count: 0 content: copy []]]
    ]

    print [{== Parsing [} to-local-file file {]}]
    parse/all read file [
      any
      [ key-rule
      | section-rule
      | copy line thru lf (all [current append current/content trim/tail line current/line-count: current/line-count + 1])
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
      find-line: funct [section /with current /post] [
        section: to-string section result: 1
        foreach [label content] sections [
          case [
            label = section [
              break
            ]
            all [
              not find replaced label
              do get to-lit-word pick [{<=} {<}] to-logic post (load label) (load either with [to-string current] [section])
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

        ; === Pre-Actions ===
        do process-actions: funct [actions] [
          foreach [action arg] actions [
            switch action [
              copy [
                target: either actions = section/post-actions [find-line/with/post arg step] [find-line/with arg step]
                print [{  . Copying from [} arg {]} sections/(to-string arg)/line-count {lines at line} target]
              ]
              highlight [
                target: either actions = section/post-actions [find-line/with/post arg step] [find-line/with arg step]
                print [{  . Highlighting to beginning of [} arg {], line} target]
                exporter/highlight target - exporter/current
              ]
              move [
                move-to find-line step
              ]
              pause [
                print [{  . Pausing} arg {seconds}]
                exporter/pause arg
              ]
              rate [
                print rejoin [{  . Set rate to } arg/1 either 2 = length? arg [rejoin [{ +/-} to-integer (1000 * arg/2) {ms}]] [{}] { cps}]
                exporter/rate arg
              ]
              replace [
                arg: to-string arg
                either not find replaced arg [
                  move-to target: either actions = section/post-actions [find-line/with/post arg step] [find-line/with arg step]
                  print [{  . Replacing [} arg {], removing} sections/(arg)/line-count {lines at line} target]
                  exporter/remove sections/(arg)/line-count
                  remove/part at exporter/data target sections/(arg)/line-count
                  append replaced arg
                ] [
                  print [{!! Aborting: trying to replace [} arg {] which was already replaced earlier}]
                  break
                ]
              ]
              save [
                print [{  . Saving document}]
                exporter/save
              ]
              scroll [
                print [{  . Scrolling [} arg {] lines}]
                exporter/scroll arg
              ]
              send [
                print [{  . Sending [} arg {]}]
                exporter/send arg
              ]
              window [
                print [{  . Focusing window [} arg {]}]
                exporter/window arg
              ]
            ]
          ]
        ] section/pre-actions

        ; === Insertion ===
        move-to find-line step
        print [{  . Inserting} section/line-count {lines}]
        exporter/insert section/content
        insert at exporter/data find-line step section/content
        exporter/current: exporter/current + section/line-count

        ; === Post-Actions ===
        do process-actions section/post-actions
      ]

      ; === Saving
      print [{== Saving [} to-local-file exporter/file {]}]
      exporter/export

      end: now/precise/time
      print [{== [} (end - begin) {] Success!}]
    ]
  ] [
    print [{!! Can't process, found duplicated steps [} unique collect [forall steps [if find next steps steps/1 [keep steps/1]]] {]}]
  ]
] [
  print [{== Usage:} to-local-file second split-path system/options/script {[textfile]}]
]
