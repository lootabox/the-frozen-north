#include "inc_sql"

int StartingConditional()
{
    if (SQLocalsPlayer_GetInt(GetPCSpeaker(), GetLocalString(OBJECT_SELF, "ship2_known")) == 1)
    {
        return TRUE;
    }
    {
        return FALSE;
    }
}
