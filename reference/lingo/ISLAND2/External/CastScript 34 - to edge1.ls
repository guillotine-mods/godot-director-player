on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie, meetings, effectspath
  if whereami = label("gate") then
    if item 1 of meetings <> "murder1" then
      sprite(6).visible = 1
      ifmovie = "1,gatetoedge1"
      newsyz = 5
      y = 320
      x = 494
      y2 = 243
      x2 = 335
    else
      sound playFile 1, effectspath & "clik3.aif"
    end if
  else
    if whereami = label("edge2") then
      ifmovie = "0,0"
      newsyz = 9
      y = 380
      x = 200
      y2 = 390
      x2 = 400
    end if
  end if
  if item 1 of meetings <> "murder1" then
    egozv = y
    egozh = x
    put x2 into item 2 of nextroomdata
    put y2 into item 3 of nextroomdata
    put "edge1" into item 1 of nextroomdata
    walkonby()
  end if
end
