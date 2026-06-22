/// <reference path="../pb_data/types.d.ts" />
//
// Adds the device_tokens collection — registry of FCM registration tokens
// used to deliver true push notifications (background / app-killed) via the
// coplan-push sidecar.
//
// Unlike the household-scoped collections, device tokens belong to a single
// USER (a person's phone), not to a household — a user may belong to several
// households but has one device. Access is therefore scoped to the owning user.
//
// Fields:
//   user      – required, the owner (auth user id)
//   token     – required, the FCM registration token (unique)
//   platform  – "android" | "web" | "ios"
//   last_seen – ISO timestamp of the most recent (re)registration
//
// A unique index on `token` lets the client upsert: the same physical device
// keeps one row even as the user logs in/out.

migrate(
  (db) => {
    const dao = new Dao(db);

    const col = new Collection();
    col.name = "device_tokens";
    col.type = "base";
    // User-scoped: you can only see / manage your own device rows.
    col.listRule   = "user = @request.auth.id";
    col.viewRule   = "user = @request.auth.id";
    col.createRule = "user = @request.auth.id";
    col.updateRule = "user = @request.auth.id";
    col.deleteRule = "user = @request.auth.id";

    col.schema = new Schema([
      Object.assign(new SchemaField(), {
        name: "user", type: "relation", required: true,
        options: { collectionId: dao.findCollectionByNameOrId("users").id, maxSelect: 1, cascadeDelete: true },
      }),
      Object.assign(new SchemaField(), { name: "token",     type: "text", required: true  }),
      Object.assign(new SchemaField(), { name: "platform",  type: "text", required: false }),
      Object.assign(new SchemaField(), { name: "last_seen", type: "text", required: false }),
    ]);

    // Unique token so re-registration replaces rather than duplicates.
    col.indexes = [
      "CREATE UNIQUE INDEX idx_device_tokens_token ON device_tokens (token)",
    ];

    dao.saveCollection(col);
  },
  (db) => {
    const dao = new Dao(db);
    dao.deleteCollection(dao.findCollectionByNameOrId("device_tokens"));
  }
);
