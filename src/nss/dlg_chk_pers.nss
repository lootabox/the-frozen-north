#include "inc_persist"
// Persuade against persuade_dc local variable, offer 1 attempt per 15min
// set script param "dc" to use that instead

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    string sTag = GetTag(OBJECT_SELF);
    int nSkill = SKILL_PERSUADE;
    int nDC = GetLocalInt(OBJECT_SELF, "persuade_dc");
    int nScriptParam = StringToInt(GetScriptParam("dc"));

    if (nScriptParam != 0)
    {
        nDC = nScriptParam;
    }

    if(!(GetIsSkillSuccessful(oPC, nSkill, nDC)))
    {
        SetTemporaryInt(GetPCPublicCDKey(oPC, TRUE)+GetName(oPC)+"_"+GetTag(OBJECT_SELF)+"_pers", 1, 900.0);
        return FALSE;
    }

    return TRUE;
}
