package sqlite

import (
    gormSqlite "gorm.io/driver/sqlite"
    "gorm.io/gorm"
    "gorm.io/gorm/clause"
    "gorm.io/gorm/schema"
)

type Dialector struct {
    inner gorm.Dialector
}

func Open(dsn string) Dialector {
    return Dialector{inner: gormSqlite.Open(dsn)}
}

func (d Dialector) Name() string { return d.inner.Name() }
func (d Dialector) Initialize(db *gorm.DB) error { return d.inner.Initialize(db) }
func (d Dialector) Migrator(db *gorm.DB) gorm.Migrator { return d.inner.Migrator(db) }
func (d Dialector) DataTypeOf(field *schema.Field) string { return d.inner.DataTypeOf(field) }
func (d Dialector) DefaultValueOf(field *schema.Field) clause.Expression { return d.inner.DefaultValueOf(field) }
func (d Dialector) BindVarTo(writer clause.Writer, stmt *gorm.Statement, v interface{}) { d.inner.BindVarTo(writer, stmt, v) }
func (d Dialector) QuoteTo(writer clause.Writer, s string) { d.inner.QuoteTo(writer, s) }
func (d Dialector) Explain(sql string, vars ...interface{}) string { return d.inner.Explain(sql, vars...) }
