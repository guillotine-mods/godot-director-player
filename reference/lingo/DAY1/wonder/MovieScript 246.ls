on peoplefunk
  global globalday, nextroomdata, meetings
  if (item 1 of nextroomdata = "shore2") and (item 3 of meetings <> "done") and (item 2 of meetings = "done") and (globalday = 1) then
    go(1, "mrfday1.dxr")
  else
    if (item 1 of nextroomdata = "clif2") and (item 1 of meetings <> "done") and (globalday = 1) then
      go(1, "murder1.dxr")
    else
      if (item 1 of nextroomdata = "veranda") and (item 2 of meetings <> "done") and (globalday = 1) then
        go(1, "hatday1.dxr")
      else
        if (item 1 of nextroomdata = "field") and (item 5 of meetings <> "done") and (item 2 of meetings = "done") and (globalday = 1) then
          go(1, "patday1.dxr")
        else
          if (item 1 of nextroomdata = "dwarfs") and (item 2 of meetings <> "done") and (globalday = 2) then
            go(1, "hatday2.dxr")
          else
            if (item 1 of nextroomdata = "path2") and (item 3 of meetings <> "done") and (globalday = 2) then
              go(1, "menaday2.dxr")
            else
              if (item 1 of nextroomdata = "rachbal") and (item 2 of meetings <> "done") and (globalday = 3) then
                go(1, "hatday3.dxr")
              else
                if (item 1 of nextroomdata = "veranda") and (item 3 of meetings <> "done") and (globalday = 3) and (item 2 of meetings = "done") then
                  go(1, "hatsikum.dxr")
                end if
              end if
            end if
          end if
        end if
      end if
    end if
  end if
  repeat with i = 18 to 21
    puppetSprite(i, 0)
  end repeat
  if item 1 of nextroomdata = "field" then
    peoplecont(1)
  else
    if item 1 of nextroomdata = "tennis" then
      peoplecont(2)
    else
      if item 1 of nextroomdata = "edge1" then
        if globalday <> 3 then
          peoplecont(3)
        else
          sprite(18).visible = 0
          sprite(20).visible = 0
        end if
      else
        if item 1 of nextroomdata = "veranda" then
          peoplecont(4)
        else
          if item 1 of nextroomdata = "dwarfs" then
            dwarfscont(8)
            dwarfscont(9)
          else
            if item 1 of nextroomdata = "exitforest3" then
              dwarfscont2(10)
            else
              isthere = "no"
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
