#include "cmodel.h"

#include <cstdio>
#include <cassert>

#define CONFIG_URI "http://www.nic.cz/ns/router/uci-raw"

class ConfigModel::Elem {
public:
	virtual ~Elem() {}
};

class ConfigModel::Option : public Elem {
protected:
	Option(const QDomElement &optionElement, const ConfigModel *model, int order, const Section *s, const QString &val) :
		name(optionElement.namedItem("name").toElement().text()),
		value(val),
		nameIdx(model->createIndex(order, 0, this)),
		valIdx(model->createIndex(order, 1, this)),
		parent(s)
	{}
public:
	const QString name, value;
	const QModelIndex nameIdx, valIdx;
	const Section *parent;
};

class ConfigModel::SimpleOption : public Option {
public:
	SimpleOption(const QDomElement &optionElement, const ConfigModel *model, int order, const Section *s) :
		Option(optionElement, model, order, s, optionElement.namedItem("value").toElement().text())
	{}
};

class ConfigModel::Value : public Elem {
public:
	Value(const QDomElement &valueElement, const ConfigModel *model, int order, const ListOption *o) :
		name(valueElement.namedItem("index").toElement().text()),
		value(valueElement.namedItem("content").toElement().text()),
		nameIdx(model->createIndex(order, 0, this)),
		valueIdx(model->createIndex(order, 1, this)),
		parent(o)
	{}
	const QString name, value;
	const QModelIndex nameIdx, valueIdx;
	const ListOption *parent;
};

class ConfigModel::ListOption : public Option {
public:
	ListOption(const QDomElement &optionElement, const ConfigModel *model, int order, const Section *s) :
		Option(optionElement, model, order, s, "")
	{
		const QDomNodeList &valueElems(optionElement.elementsByTagNameNS(CONFIG_URI, "value"));
		for (int i = 0; i < valueElems.count(); i ++)
			values << new Value(valueElems.at(i).toElement(), model, i, this);
	}
	QList<const Value *> values;
};

class ConfigModel::Section : public Elem {
public:
	Section(const QDomElement &sectionElement, const ConfigModel *model, int order, const ConfigFile *cf) :
		name(sectionElement.namedItem("name").toElement().text()),
		type(sectionElement.namedItem("type").toElement().text()),
		anonymous(!sectionElement.namedItem("anonymous").isNull()),
		nameIdx(model->createIndex(order, 0, this)),
		typeIdx(model->createIndex(order, 1, this)),
		parent(cf)
	{
		const QDomNodeList &children(sectionElement.childNodes());
		for (int i = 0; i < children.count(); i ++) {
			if (!children.at(i).isElement())
				continue;
			const QDomElement &child(children.at(i).toElement());
			const QString &ns(child.namespaceURI());
			if (ns != CONFIG_URI)
				continue;
			const QString &name(child.tagName());
			if (name == "option")
				options << new SimpleOption(child, model, options.count(), this);
			else if (name == "list")
				options << new ListOption(child, model, options.count(), this);
		}
	}
	const QString name, type;
	const bool anonymous;
	const QModelIndex nameIdx, typeIdx;
	const ConfigFile *parent;
	QList<const Option *> options;
};

class ConfigModel::ConfigFile : public Elem {
public:
	ConfigFile(const QDomElement &configElement, const ConfigModel *model, int order) :
		name(configElement.namedItem("name").toElement().text()),
		index(model->createIndex(order, 0, this)),
		tidx(model->createIndex(order, 1, this))
	{
		const QDomNodeList &sectionElements(configElement.elementsByTagNameNS(CONFIG_URI, "section"));
		for (int i = 0; i < sectionElements.count(); i ++)
			sections << new Section(sectionElements.at(i).toElement(), model, i, this);
	}
	const QString name;
	QList<const Section *> sections;
	const QModelIndex index, tidx;
};

ConfigModel::ConfigModel(const QDomDocument &configData_) :
	configData(configData_)
{
	// The namespace trick doesn't neem to work for some reason. OK, whatever.
	const QDomNodeList &configElements(configData.documentElement().elementsByTagNameNS(CONFIG_URI, "config"));
	for (int i = 0; i < configElements.count(); i ++)
		configs << new ConfigFile(configElements.at(i).toElement(), this, i);
}

QModelIndex ConfigModel::index(int row, int column, const QModelIndex &parent) const {
	if (parent.isValid()) {
		const Elem *data = static_cast<const Elem *>(parent.internalPointer());
		const ConfigFile *cf = dynamic_cast<const ConfigFile *>(data);
		const Section *s = dynamic_cast<const Section *>(data);
		const ListOption *l = dynamic_cast<const ListOption *>(data);
		if (cf) {
			const Section *s = cf->sections[row];
			return column ? s->typeIdx : s->nameIdx;
		} else if (s) {
			const Option *o = s->options[row];
			return column ? o->valIdx : o->nameIdx;
		} else if (l) {
			const Value *v = l->values[row];
			return column ? v->valueIdx : v->nameIdx;
		} else
			assert(0);
	} else
		return column ? configs[row]->tidx : configs[row]->index;
}

QModelIndex ConfigModel::parent(const QModelIndex &index) const {
	const Elem *data = static_cast<const Elem *>(index.internalPointer());
	const ConfigFile *cf = dynamic_cast<const ConfigFile *>(data);
	if (cf)
		return QModelIndex();
	const Section *s = dynamic_cast<const Section *>(data);
	if (s)
		return s->parent->index;
	const Option *o = dynamic_cast<const Option *>(data);
	if (o)
		return o->parent->nameIdx;
	const Value *v = dynamic_cast<const Value *>(data);
	if (v)
		return v->parent->nameIdx;
	assert(0);
}

int ConfigModel::rowCount(const QModelIndex &parent) const {
	if (parent.isValid()) {
		const Elem *data = static_cast<const Elem *>(parent.internalPointer());
		const ConfigFile *cf = dynamic_cast<const ConfigFile *>(data);
		const Section *s = dynamic_cast<const Section *>(data);
		const ListOption *l = dynamic_cast<const ListOption *>(data);
		if (cf)
			return cf->sections.size();
		else if (s)
			return s->options.size();
		else if (l)
			return l->values.size();
		else
			return 0;
	} else
		return configs.size();
}

int ConfigModel::columnCount(const QModelIndex &parent) const {
	if (parent.isValid()) {
		const Elem *data = static_cast<const Elem *>(parent.internalPointer());
		const ConfigFile *cf = dynamic_cast<const ConfigFile *>(data);
		const Section *s = dynamic_cast<const Section *>(data);
		const ListOption *l = dynamic_cast<const ListOption *>(data);
		if (cf || s || l)
			return 2;
		else
			return 0;
	} else
		return 2;
}

QVariant ConfigModel::data(const QModelIndex &index, int role) const {
	const Elem *data = static_cast<const Elem *>(index.internalPointer());
	const ConfigFile *cf = dynamic_cast<const ConfigFile *>(data);
	const Section *s = dynamic_cast<const Section *>(data);
	const Option *o = dynamic_cast<const Option *>(data);
	const Value *v = dynamic_cast<const Value *>(data);
	switch (role) {
		case Qt::DisplayRole:
			if (cf)
				return index.column() ? "config" : cf->name;
			if (s)
				return index.column() ? s->type : s->name;
			if (o)
				return index.column() ? o->value : o->name;
			if (v)
				return index.column() ? v->value : v->name;
		case Qt::DecorationRole:
			if (index.column())
				return QVariant();
			if (cf)
				return Qt::yellow;
			if (s)
				return Qt::red;
			if (v || dynamic_cast<const SimpleOption *>(data))
				return Qt::blue;
			if (o)
				return Qt::green;
		default:
			return QVariant();
	}
}

QVariant ConfigModel::headerData(int section, Qt::Orientation orientation, int role) const {
	if (orientation != Qt::Horizontal || role != Qt::DisplayRole)
		return QVariant();
	return section ? "type/value" : "name";
}
