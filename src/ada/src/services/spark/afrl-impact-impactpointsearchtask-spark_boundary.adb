package body AFRL.impact.ImpactPointSearchTask.SPARK_Boundary with SPARK_Mode => Off is

   function Get_SearchLocationID (X : ImpactPointSearchTask) return Int64 renames
     getSearchLocationID;

end AFRL.impact.ImpactPointSearchTask.SPARK_Boundary;
