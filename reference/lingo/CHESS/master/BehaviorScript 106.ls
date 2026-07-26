on mouseUp
  global soundspath
  repeat with y = 1 to 5
    repeat with x = 1 to 5
      if item x of line y of field "board" = "H" then
        yy = y
        xx = x
      end if
    end repeat
  end repeat
  if the clickOn = 51 then
    if (yy <> 1) and (item xx of line yy - 1 of field "board" <> "n") then
      if item xx of line yy - 1 of field "board" contains "e" then
        sound playFile 1, soundspath & "artntsu" & random(5) & ".aif"
      else
        put "0" into item xx of line yy of field "board"
        put "H" into item xx of line yy - 1 of field "board"
        z = item xx of line yy - 1 of field "hezsprite"
        set the visible of sprite value(item xx of line yy of field "hezsprite") to 0
        set the visible of sprite value(z) to 1
        sound playFile 1, soundspath & "arthzmov1.aif"
        badmov()
        updateStage()
      end if
    else
      sound playFile 1, soundspath & "artntmv" & random(5) & ".aif"
    end if
  else
    if the clickOn = 58 then
      if (yy <> 1) and (xx <> 1) and (item xx - 1 of line yy - 1 of field "board" <> "n") then
        if item xx - 1 of line yy - 1 of field "board" contains "e" then
          sound playFile 1, soundspath & "artntsu" & random(5) & ".aif"
        else
          put "0" into item xx of line yy of field "board"
          put "H" into item xx - 1 of line yy - 1 of field "board"
          z = item xx - 1 of line yy - 1 of field "hezsprite"
          set the visible of sprite value(item xx of line yy of field "hezsprite") to 0
          set the visible of sprite value(z) to 1
          sound playFile 1, soundspath & "arthzmov5.aif"
          badmov()
          updateStage()
        end if
      else
        if (xx = 1) and (yy <> 1) then
          go("winner")
        else
          sound playFile 1, soundspath & "artntmv" & random(5) & ".aif"
        end if
      end if
    else
      if the clickOn = 52 then
        if (yy <> 1) and (xx <> 5) and (item xx + 1 of line yy - 1 of field "board" <> "n") then
          if item xx + 1 of line yy - 1 of field "board" contains "e" then
            sound playFile 1, soundspath & "artntsu" & random(5) & ".aif"
          else
            put "0" into item xx of line yy of field "board"
            put "H" into item xx + 1 of line yy - 1 of field "board"
            z = item xx + 1 of line yy - 1 of field "hezsprite"
            set the visible of sprite value(item xx of line yy of field "hezsprite") to 0
            set the visible of sprite value(z) to 1
            sound playFile 1, soundspath & "arthzmov6.aif"
            badmov()
            updateStage()
          end if
        else
          sound playFile 1, soundspath & "artntmv" & random(5) & ".aif"
        end if
      else
        if the clickOn = 55 then
          if (yy <> 5) and (item xx of line yy + 1 of field "board" <> "n") then
            if item xx of line yy + 1 of field "board" contains "e" then
              sound playFile 1, soundspath & "artntsu" & random(5) & ".aif"
            else
              put "0" into item xx of line yy of field "board"
              put "H" into item xx of line yy + 1 of field "board"
              z = item xx of line yy + 1 of field "hezsprite"
              set the visible of sprite value(item xx of line yy of field "hezsprite") to 0
              set the visible of sprite value(z) to 1
              sound playFile 1, soundspath & "arthzmov2.aif"
              badmov()
              updateStage()
            end if
          else
            sound playFile 1, soundspath & "artntmv" & random(5) & ".aif"
          end if
        else
          if the clickOn = 56 then
            if (yy <> 5) and (xx <> 1) and (item xx - 1 of line yy + 1 of field "board" <> "n") then
              if item xx - 1 of line yy + 1 of field "board" contains "e" then
                sound playFile 1, soundspath & "artntsu" & random(5) & ".aif"
              else
                put "0" into item xx of line yy of field "board"
                put "H" into item xx - 1 of line yy + 1 of field "board"
                z = item xx - 1 of line yy + 1 of field "hezsprite"
                set the visible of sprite value(item xx of line yy of field "hezsprite") to 0
                set the visible of sprite value(z) to 1
                sound playFile 1, soundspath & "arthzmov7.aif"
                badmov()
                updateStage()
              end if
            else
              if (xx = 1) and (y <> 5) then
                go("winner")
              else
                sound playFile 1, soundspath & "artntmv" & random(5) & ".aif"
              end if
            end if
          else
            if the clickOn = 54 then
              if (yy <> 5) and (xx <> 5) and (item xx + 1 of line yy + 1 of field "board" <> "n") then
                if item xx + 1 of line yy + 1 of field "board" contains "e" then
                  sound playFile 1, soundspath & "artntsu" & random(5) & ".aif"
                else
                  put "0" into item xx of line yy of field "board"
                  put "H" into item xx + 1 of line yy + 1 of field "board"
                  z = item xx + 1 of line yy + 1 of field "hezsprite"
                  set the visible of sprite value(item xx of line yy of field "hezsprite") to 0
                  set the visible of sprite value(z) to 1
                  sound playFile 1, soundspath & "arthzmov8.aif"
                  badmov()
                  updateStage()
                end if
              else
                sound playFile 1, soundspath & "artntmv" & random(5) & ".aif"
              end if
            else
              if the clickOn = 53 then
                if (xx <> 5) and (item xx + 1 of line yy of field "board" <> "n") then
                  if item xx + 1 of line yy of field "board" contains "e" then
                    sound playFile 1, soundspath & "artntsu" & random(5) & ".aif"
                  else
                    put "0" into item xx of line yy of field "board"
                    put "H" into item xx + 1 of line yy of field "board"
                    z = item xx + 1 of line yy of field "hezsprite"
                    set the visible of sprite value(item xx of line yy of field "hezsprite") to 0
                    set the visible of sprite value(z) to 1
                    sound playFile 1, soundspath & "arthzmov3.aif"
                    badmov()
                    updateStage()
                  end if
                else
                  sound playFile 1, soundspath & "artntmv" & random(5) & ".aif"
                end if
              else
                if the clickOn = 57 then
                  if (xx <> 1) and (item xx - 1 of line yy of field "board" <> "n") then
                    if item xx - 1 of line yy of field "board" contains "e" then
                      sound playFile 1, soundspath & "artntsu" & random(5) & ".aif"
                    else
                      put "0" into item xx of line yy of field "board"
                      put "H" into item xx - 1 of line yy of field "board"
                      z = item xx - 1 of line yy of field "hezsprite"
                      set the visible of sprite value(item xx of line yy of field "hezsprite") to 0
                      set the visible of sprite value(z) to 1
                      sound playFile 1, soundspath & "arthzmov4.aif"
                      badmov()
                      updateStage()
                    end if
                  else
                    if xx = 1 then
                      go("winner")
                    else
                      sound playFile 1, soundspath & "artntmv" & random(5) & ".aif"
                    end if
                  end if
                end if
              end if
            end if
          end if
        end if
      end if
    end if
  end if
end
