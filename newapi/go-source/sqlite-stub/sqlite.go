package sqlite
import (
    "gorm.io/gorm"
    "gorm.io/gorm/clause"
    "gorm.io/gorm/migrator"
    "gorm.io/gorm/schema"
)
type Dialector struct{ DSN string }
func Open(dsn string) Dialector { return Dialector{DSN: dsn} }
func (Dialector) Name() string { return "sqlite" }
func (Dialector) Initialize(*gorm.DB) error { return gorm.ErrInvalidDB }
func (Dialector) Migrator(*gorm.DB) gorm.Migrator { return &migrator.Migrator{} }
func (Dialector) DataTypeOf(*schema.Field) string { return "" }
func (Dialector) DefaultValueOf(*schema.Field) clause.Expression { return nil }
func (Dialector) BindVarTo(writer clause.Writer, stmt *gorm.Statement, v interface{}) { writer.WriteString("?") }
func (Dialector) QuoteTo(writer clause.Writer, s string) { writer.WriteString(s) }
func (Dialector) Explain(sql string, vars ...interface{}) string { return sql }
