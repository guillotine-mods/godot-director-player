on exitFrame
  if rollOver(4) then
    set the memberNum of sprite 4 to the number of member "cbook1" of castLib "book"
  else
    set the memberNum of sprite 4 to the number of member "book1" of castLib "book"
    if rollOver(5) then
      set the memberNum of sprite 5 to the number of member "cafgani" of castLib "book"
    else
      set the memberNum of sprite 5 to the number of member "afgani" of castLib "book"
      if rollOver(6) then
        set the memberNum of sprite 6 to the number of member "cbook2" of castLib "book"
      else
        set the memberNum of sprite 6 to the number of member "book2" of castLib "book"
        if rollOver(7) then
          set the memberNum of sprite 7 to the number of member "cbook4" of castLib "book"
        else
          set the memberNum of sprite 7 to the number of member "book4" of castLib "book"
          if rollOver(8) then
            set the memberNum of sprite 8 to the number of member "cbook3" of castLib "book"
          else
            set the memberNum of sprite 8 to the number of member "book3" of castLib "book"
            if rollOver(9) then
              set the memberNum of sprite 9 to the number of member "cbook5" of castLib "book"
            else
              set the memberNum of sprite 9 to the number of member "book5" of castLib "book"
            end if
          end if
        end if
      end if
    end if
  end if
end
