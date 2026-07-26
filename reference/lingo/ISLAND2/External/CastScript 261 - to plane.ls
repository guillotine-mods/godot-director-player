on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie
  if whereami = label("fort") then
    ifmovie = "0,0"
    newsyz = 4
    y = 430
    x = 570
    y2 = 210
    x2 = 10
  end if
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "plane" into item 1 of nextroomdata
  repeat with i = 1 to the number of lines in field "plane" of castLib "master"
    sprite(39 + i).visible = 0
    case line i of field "plane" of castLib "master" of
      "igkey":
        sprite(40).visible = 1
      "joystk":
        sprite(41).visible = 1
      "fuel":
        sprite(47).visible = 1
      "rotor":
        sprite(48).visible = 1
      "shoes":
        sprite(46).visible = 1
      "spring":
        sprite(45).visible = 1
      "prplor":
        sprite(49).visible = 1
      "engine":
        sprite(43).visible = 1
      "chairs":
        sprite(42).visible = 1
      "chair2":
        sprite(44).visible = 1
    end case
  end repeat
  walkonby()
end
