pageextension 70009 VNPAYPOSTerminalCard extends "LSC Store Card"
{
    layout
    {
        addafter("Statement/Closing")
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
            group("VCB Integration Setup")
            {
                Caption = 'VCB Integration Setup';

                field("Enable VCB Integration"; Rec."Enable VCB Integration")
                {
                    ApplicationArea = All;
                }
                field("VCB Payment Service URL"; Rec."VCB Payment Service URL")
                {
                    ApplicationArea = All;
                }
                field("VCB Terminal ID"; Rec."VCB Terminal ID")
                {
                    ApplicationArea = All;
                }
                field("VCB Merchant ID"; Rec."VCB Merchant ID")
                {
                    ApplicationArea = All;
                }
                field("VCB Tender Type Code"; Rec."VCB Tender Type Code")
                {
                    ApplicationArea = All;
                }
                field("VCB First Check Delay Sec"; Rec."VCB First Check Delay Sec")
                {
                    ApplicationArea = All;
                }
                field("VCB Check Interval Sec"; Rec."VCB Check Interval Sec")
                {
                    ApplicationArea = All;
                }
                field("VCB Max Retries"; Rec."VCB Max Retries")
                {
                    ApplicationArea = All;
                }
            }

        }
    }
}






















































