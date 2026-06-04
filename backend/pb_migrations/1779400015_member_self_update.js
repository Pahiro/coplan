// Allow members to update their own household_members record (e.g. preferred_color).
// Previously only the household owner could update member records.
migrate(
  (db) => {
    const dao = new Dao(db);
    const col = dao.findCollectionByNameOrId("household_members");
    col.updateRule = "household.owner = @request.auth.id || user = @request.auth.id";
    dao.saveCollection(col);
  },
  (db) => {
    const dao = new Dao(db);
    const col = dao.findCollectionByNameOrId("household_members");
    col.updateRule = "household.owner = @request.auth.id";
    dao.saveCollection(col);
  }
);
