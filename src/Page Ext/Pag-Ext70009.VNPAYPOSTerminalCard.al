pageextension 70009 VNPAYPOSTerminalCard extends "LSC POS Terminal Card"
{
    layout
    {
        addafter("VCB Integration Setup")
        {
            group("VNPay Integration Setup")
            {
                field("Enable VNPay Integration"; Rec."Enable VNPay Integration")
                {
                    ApplicationArea = All;
                }
            }
        }
    }
}
