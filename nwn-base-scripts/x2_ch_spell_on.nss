//::///////////////////////////////////////////////
//:: Turn On Spell
//:: X2_CH_SPELL_ON.nss
//:: Copyright (c) 2001 Bioware Corp.
//:://////////////////////////////////////////////
//:://////////////////////////////////////////////
//:: Created By: Brent
//:: Created On: June 2003
//:://////////////////////////////////////////////
#include "NW_I0_GENERIC"

void main()
{
    SetLocalInt(OBJECT_SELF, "X2_L_STOPCASTING", 0);
}


