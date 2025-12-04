pageextension 70008 "Ewallet Tender Type Page" extends "LSC Tender Type Card"
{
    layout
    {
        addafter("Declaration")
        {
            group("VNPay Integration")
            {
                field("VNPay Dual Display"; Rec."VNPay Dual Display")
                {
                    ApplicationArea = All;
                }
                field("VNPay QR Panel"; Rec."VNPay QR Panel")
                {
                    ApplicationArea = All;
                }
            }
        }
    }
}