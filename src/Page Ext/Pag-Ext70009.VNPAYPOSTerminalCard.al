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
                field("VNPAY Payment Service URL"; Rec."VNPAY Payment Service URL")
                {
                    ApplicationArea = All;
                }
                field("VNPAY Terminal ID"; Rec."VNPAY Terminal ID")
                {
                    ApplicationArea = All;
                }
                field("VNPAY Merchant ID"; Rec."VNPAY Merchant ID")
                {
                    ApplicationArea = All;
                }
                field("VNPay Time Out"; Rec."VNPay Time Out")
                {
                    ApplicationArea = All;
                }
                field("VNPay Max Retries"; Rec."VNPay Max Retries")
                {
                    ApplicationArea = All;
                }
                field("VNPAY First Check Delay Sec"; Rec."VNPAY First Check Delay Sec")
                {
                    ApplicationArea = All;
                }
                field("VNPAY Check Interval Sec"; Rec."VNPAY Check Interval Sec")
                {
                    ApplicationArea = All;
                }
            }
        }
    }
}