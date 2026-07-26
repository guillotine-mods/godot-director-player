on badmov
  global ches1, ches2, soundspath
  go("badmov")
  repeat with y = 1 to 5
    repeat with x = 1 to 5
      if item x of line y of field "board" = "E1" then
        yyE1 = y
        xxE1 = x
        next repeat
      end if
      if item x of line y of field "board" = "E2" then
        yyE2 = y
        xxE2 = x
        next repeat
      end if
      if item x of line y of field "board" = "H" then
        yyH = y
        xxH = x
      end if
    end repeat
  end repeat
  movinbad("E1", ches1, xxE1, yyE1, xxH, yyH)
  sound playFile 1, soundspath & "artmv" & ches1 & ".aif"
  movinbad("E2", ches2, xxE2, yyE2, xxH, yyH)
  sound playFile 1, soundspath & "artmv" & ches2 & ".aif"
end

on movinbad hisnum, whatkind, x, y, xh, yh
  set the visible of sprite value(item x of line y of field "enesprite") to 0
  oldx = x
  oldy = y
  if (whatkind = "map") or (whatkind = "pat") then
    if ((x - xh) = 0) or ((y - yh) = 0) then
      set the memberNum of sprite value(item xh of line yh of field "enesprite") to the number of member (whatkind & "fig")
      set the visible of sprite value(item xh of line yh of field "enesprite") to 1
      x = xh
      y = yh
      set the visible of sprite value(item x of line y of field "enesprite") to 0
      put "0" into item oldx of line oldy of field "board"
      go("loser")
    else
      z = random(2)
      if z = 1 then
        ddd = 0
        repeat while ddd = 0
          x = random(5)
          if (item x of line y of field "board" = "n") or (item x of line y of field "board" contains "e") then
            ddd = 0
            next repeat
          end if
          ddd = 1
        end repeat
      else
        ddd = 0
        repeat while ddd = 0
          y = random(5)
          if (item x of line y of field "board" = "n") or (item x of line y of field "board" contains "e") then
            ddd = 0
            next repeat
          end if
          ddd = 1
        end repeat
      end if
    end if
  else
    if (whatkind = "suz") or (whatkind = "rin") then
      if (item x + 1 of line y + 1 of field "board" = "H") or (item x - 1 of line y - 1 of field "board" = "H") or (item x + 1 of line y - 1 of field "board" = "H") or (item x - 1 of line y + 1 of field "board" = "H") then
        set the memberNum of sprite value(item xh of line yh of field "enesprite") to the number of member (whatkind & "fig")
        set the visible of sprite value(item xh of line yh of field "enesprite") to 1
        x = xh
        y = yh
        set the visible of sprite value(item x of line y of field "enesprite") to 0
        put "0" into item oldx of line oldy of field "board"
        go("loser")
      else
        d = xh - x
        if d < 0 then
          if random(3) <> 1 then
            x = x - 1
          end if
        end if
        if d > 0 then
          if random(3) <> 1 then
            x = x + 1
          end if
        end if
        if x > 5 then
          x = 5
        end if
        if x < 1 then
          x = 1
        end if
        d = yh - y
        if d < 0 then
          y = y - 1
        end if
        if d > 0 then
          y = y + 1
        end if
        if y > 5 then
          y = 5
        end if
        if y < 1 then
          y = 1
        end if
        if (item x of line y of field "board" = "n") or (item x of line y of field "board" contains "e") or (item x of line y of field "board" = "H") then
          x = oldx
          y = oldy
        end if
      end if
    else
      if whatkind = "jos" then
        if (((xh - x) = 1) or ((xh - x) = -1)) and (((yh - y) = 1) or ((yh - y) = -1)) then
          set the memberNum of sprite value(item xh of line yh of field "enesprite") to the number of member (whatkind & "fig")
          set the visible of sprite value(item xh of line yh of field "enesprite") to 1
          x = xh
          y = yh
          set the visible of sprite value(item x of line y of field "enesprite") to 0
          put "0" into item oldx of line oldy of field "board"
          go("loser")
        else
          if (xh - x) > 0 then
            x = x + 1
          end if
          if (xh - x) < 1 then
            x = x - 1
          end if
          if x > 5 then
            x = 5
          end if
          if x < 1 then
            x = 1
          end if
          if (item x of line y of field "board" = "n") or (item x of line y of field "board" contains "e") or (item x of line y of field "board" = "H") then
            x = oldx
            y = oldy
          end if
        end if
      else
        if (whatkind = "hez") or (whatkind = "mrf") then
          fin = 0
          x1 = x
          y1 = y
          repeat while fin <> "ok"
            if (x1 = 1) or ((x1 = 4) and (y1 = 4)) then
              fin = "ok"
              next repeat
            end if
            x1 = x1 - 1
            y1 = y1 + 1
          end repeat
          repeat while (y1 > 0) and (x1 < 6)
            if item x1 of line y1 of field "board" = "H" then
              set the memberNum of sprite value(item xh of line yh of field "enesprite") to the number of member (whatkind & "fig")
              set the visible of sprite value(item xh of line yh of field "enesprite") to 1
              x = xh
              y = yh
              set the visible of sprite value(item x of line y of field "enesprite") to 0
              put "0" into item oldx of line oldy of field "board"
              go("loser")
              y1 = 0
              next repeat
            end if
            y1 = y1 - 1
            x1 = x1 + 1
          end repeat
          fin = 0
          x1 = x
          y1 = y
          repeat while fin <> "ok"
            if (y1 = 1) or (x1 = 1) then
              fin = "ok"
              next repeat
            end if
            x1 = x1 - 1
            y1 = y1 - 1
          end repeat
          repeat while (y1 < 6) and (x1 < 6)
            if item x1 of line y1 of field "board" = "H" then
              set the memberNum of sprite value(item xh of line yh of field "enesprite") to the number of member (whatkind & "fig")
              set the visible of sprite value(item xh of line yh of field "enesprite") to 1
              x = xh
              y = yh
              set the visible of sprite value(item x of line y of field "enesprite") to 0
              put "0" into item oldx of line oldy of field "board"
              go("loser")
              y1 = 6
              next repeat
            end if
            y1 = y1 + 1
            x1 = x1 + 1
          end repeat
          fin = "not"
          repeat while fin = "not"
            if (xh - x) > 0 then
              x1 = 5 - x
              x = x + random(x1)
            else
              if (xh - x) < 1 then
                x1 = x - 1
                x = x - random(x1)
              end if
            end if
            if (yh - y) > 0 then
              y1 = 5 - y
              y = y + random(y1)
            else
              if (yh - y) < 1 then
                y1 = y - 1
                y = y - random(y1)
              end if
            end if
            if abs(oldx - x) = abs(oldy - y) then
              if item x of line y of field "board" contains "e" then
                fin = "not"
              else
                fin = "ok"
              end if
            end if
            if (y = 1) and (x = 1) then
              fin = "not"
              next repeat
            end if
            if (y = 5) and (x > 2) then
              fin = "not"
              next repeat
            end if
            if (y = 4) and (x = 5) then
              fin = "not"
            end if
          end repeat
        end if
      end if
    end if
  end if
  set the memberNum of sprite value(item x of line y of field "enesprite") to the number of member (whatkind & "fig")
  put "0" into item oldx of line oldy of field "board"
  set the visible of sprite value(item x of line y of field "enesprite") to 1
  put hisnum into item x of line y of field "board"
end
