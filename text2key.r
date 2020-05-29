REBOL [
  title: {Text2Key}
  author: {iarwain@orx-project.org}
  date: 24-May-2020
  file: %text2key.r
]

if attempt [exists? file: to-file system/options/args/1] [

  use [current section action target] [
    label: [integer! opt ["." integer!]]
    option: [
      #":" [#"<" (action: 'copy) | #">" (action: 'replace) | #"|" (action: 'delay)] copy target label
    | (action: none target: none)
    ]
    space: charset [#" " #"^-"]
    spaces: [any space]
    comment-marker: [{//} | #";" | #"#"]
    section-marker: [
      spaces comment-marker spaces #"[" copy section label option #"]" thru lf
    ]

    sections: make hash! []
    current: do add-section: func [
      label target-action target
    ] [
      last append sections reduce [label context compose [action: target-action target: (target) line-count: 0 content: copy []]]
    ] "0" none none

    parse read file [
      any [
        section-marker (current: add-section section action target)
      | copy line thru lf (append current/content line current/line-count: current/line-count + 1)
      ]
    ]
  ]

  steps: sort/compare extract sections 2 func [a b] [(load a) < (load b)]
  either steps = unique steps [
    use [section result replaced target current] [
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
        if current != line [
          print [{  . Moving to line} line rejoin [{[} pick [{+} {}] line > current line - current {]}]]
          current: line
        ]
      ]
      result: copy [] replaced: copy [] current: 1
      foreach step steps [
        section: sections/:step
        print [{== Step [} step {]}]
        switch section/action [
          delay [
            print [{  . Delaying} load section/target {seconds}]
          ]
          copy [
            target: find-line/with section/target step
            print [{  . Copying from [} section/target {]} sections/(section/target)/line-count {lines at line} target]
          ]
          replace [
            either not find replaced section/target [
              move-to target: find-line/with section/target step
              print [{  . Replacing [} section/target {], removing} sections/(section/target)/line-count {lines at line} target]
              remove/part at result target sections/(section/target)/line-count
              append replaced section/target
            ] [
              print [{!! Aborting: trying to replace [} section/target {] which was already replaced earlier}]
              break
            ]
          ]
        ]
        move-to find-line step
        print [{  . Inserting} section/line-count {lines}]
        insert at result find-line step section/content
        current: current + section/line-count
      ]
      foreach l result [print trim/tail l]
    ]
  ] [
    print [{!! Can't process, duplicated steps found in [} steps {]}]
  ]
]

dump-sections: does [
  foreach [label section] sections [
    print [label section/action section/target section/line-count mold either empty? section/content [{}] [section/content/1]]
  ]
]

halt
