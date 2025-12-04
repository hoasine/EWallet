tableextension 70009 "POS Trans VNPAYQR ext" extends "LSC POS Transaction"
{
    trigger OnDelete()
    var
        RetailImageLink: Record "LSC Retail Image Link";
        RetailImage: Record "LSC Retail Image";
    begin
        RetailImageLink.SetRange("Record Id", Format(Rec.RecordId));
        if RetailImageLink.FindSet() then
            repeat
                if RetailImage.Get(RetailImageLink."Image Id") then
                    RetailImage.Delete();
            until RetailImageLink.Next() = 0;

        RetailImageLink.DeleteAll(true);
    end;
}
