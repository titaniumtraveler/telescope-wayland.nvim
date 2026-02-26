(element
  (STag
    (Name) @protocol
    (#eq?  @protocol "protocol")
    (#set!  kind "protocol")
    (Attribute
      (Name)     @protocol_name_key (#eq?     @protocol_name_key "name")
      (AttValue) @protocol_name_val (#offset! @protocol_name_val 0 1 0 -1)
    )
  )
)

(element
  (STag
    (Name) @interface
    (#eq?  @interface "interface")
    (#set!  kind "interface")
    (Attribute
      (Name)     @interface_name_key (#eq?     @interface_name_key "name")
      (AttValue) @interface_name_val (#offset! @interface_name_val 0 1 0 -1)
    )
  )
)

(element
  (STag
    (Name) @request
    (#eq?  @request "request")
    (#set!  kind "request")
    (Attribute
      (Name)     @request_name_key (#eq?     @request_name_key "name")
      (AttValue) @request_name_val (#offset! @request_name_val 0 1 0 -1)
    )
  )
)

(element
  (STag
    (Name) @event
    (#eq?  @event "event")
    (#set!  kind "event")
    (Attribute
      (Name)     @event_name_key (#eq?     @event_name_key "name")
      (AttValue) @event_name_val (#offset! @event_name_val 0 1 0 -1)
    )
  )
)

(element
  (STag
    (Name) @enum
    (#eq?  @enum "enum")
    (#set!  kind "enum")
    (Attribute
      (Name)     @enum_name_key (#eq?     @enum_name_key "name")
      (AttValue) @enum_name_val (#offset! @enum_name_val 0 1 0 -1)
    )
  )
)
