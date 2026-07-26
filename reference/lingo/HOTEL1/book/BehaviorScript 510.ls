on exitFrame
  global meetings
  if item 1 of meetings <> "done" then
    sprite(10).visible = 0
    sprite(12).visible = 1
  else
    sprite(12).visible = 0
  end if
end
