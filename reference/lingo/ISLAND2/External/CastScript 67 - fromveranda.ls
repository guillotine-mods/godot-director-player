on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie, meetings, effectspath
  if whereami = label("gate") then
    if item 1 of meetings <> "murder1" then
      sprite(6).visible = 1
      ifmovie = "1,gatetoveranda"
      newsyz = 9
      y = 359
      x = 321
      y2 = 360
      x2 = 600
    else
      sound playFile 1, effectspath & "clik3.aif"
    end if
  end if
  if item 1 of meetings <> "murder1" then
    egozv = y
    egozh = x
    put x2 into item 2 of nextroomdata
    put y2 into item 3 of nextroomdata
    put "veranda" into item 1 of nextroomdata
    walkonby()
  end if
end
