on peoplefunk
  global nextroomdata, meetings, globalday
  if globalday = 1 then
    if (item 1 of nextroomdata = "exitforest3") and (item 1 of meetings <> "done") then
      go(1, "nite1.dxr")
    else
      if (item 1 of nextroomdata = "edge5") and (item 2 of meetings <> "done") then
        go(1, "sabmon1.dxr")
      else
        if (item 1 of nextroomdata = "forest2") and (item 3 of meetings <> "done") then
          go(1, "figtnigt.dxr")
        else
          if (item 1 of nextroomdata = "exitforest3") and (item 4 of meetings <> "done") and (item 1 of meetings = "done") then
            go(1, "igul.dxr")
          else
            if (item 1 of nextroomdata = "check") and (item 5 of meetings <> "done") then
              go(1, "zara.dxr")
            else
              if (item 1 of nextroomdata = "path2") and (item 6 of meetings <> "done") then
                go(1, "bigel.dxr")
              else
                if (item 1 of nextroomdata = "edge1") and (item 7 of meetings <> "done") then
                  go(1, "panter.dxr")
                else
                  if (item 1 of nextroomdata = "clif2") and (item 8 of meetings <> "done") then
                    go(1, "psik.dxr")
                  end if
                end if
              end if
            end if
          end if
        end if
      end if
    end if
  end if
  if globalday = 2 then
    if (item 1 of nextroomdata = "rachbal") and (item 2 of meetings <> "done") then
      go(1, "samnight.dxr")
    else
      if (item 1 of nextroomdata = "clif") and (item 4 of meetings <> "done") then
        go(1, "fugel.dxr")
      else
        if (item 1 of nextroomdata = "shore1") and (item 5 of meetings <> "done") then
          go(1, "dagi.dxr")
        else
          if (item 1 of nextroomdata = "forest1") and (item 6 of meetings <> "done") then
            go(1, "jo.dxr")
          else
            if (item 1 of nextroomdata = "dwarfs") and (item 7 of meetings <> "done") then
              go(1, "karoz.dxr")
            else
              if (item 1 of nextroomdata = "edge2") and (item 8 of meetings <> "done") then
                go(1, "gardug.dxr")
              end if
            end if
          end if
        end if
      end if
    end if
  end if
end

on peoplecont i
  global inexits
  if item i of inexits <> "dead" then
    x = value(item i of inexits)
    x = x + 1
    if x > 10 then
      x = 1
    end if
    put x into item i of inexits
    if x > 5 then
      sprite(18).visible = 0
      sprite(19).visible = 0
      sprite(20).visible = 1
      sprite(21).visible = 1
    else
      sprite(18).visible = 1
      sprite(19).visible = 1
      sprite(20).visible = 0
      sprite(21).visible = 0
    end if
  end if
end

on dwarfscont i
  global inexits
  x = value(item i of inexits)
  x = x + 1
  if x > 10 then
    x = 1
  end if
  put x into item i of inexits
  sprite(18).visible = 0
  sprite(19).visible = 0
  sprite(20).visible = 0
  sprite(21).visible = 0
  sprite(36).visible = 0
  sprite(37).visible = 0
end

on dwarfscont2 i
  global inexits
  x = value(item i of inexits)
  x = x + 1
  if x > 8 then
    x = 1
  end if
  put x into item i of inexits
  if x > 4 then
    sprite(20).visible = 1
    sprite(18).visible = 0
  else
    sprite(18).visible = 1
    sprite(20).visible = 0
  end if
end
