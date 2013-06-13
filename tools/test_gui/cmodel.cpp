#include "cmodel.h"

#include <cstdio>
#include <cassert>

#define CONFIG_URI "http://www.nic.cz/ns/router/uci-raw"

class ConfigModel::Elem {
public:
	virtual ~Elem() {}
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
	{}
	const QString name, type;
	const bool anonymous;
	const QModelIndex nameIdx, typeIdx;
	const ConfigFile *parent;
};

class ConfigModel::ConfigFile : public Elem {
public:
	ConfigFile(const QDomElement &configElement, const ConfigModel *model, int order) :
		name(configElement.namedItem("name").toElement().text()),
		index(model->createIndex(order, 0, this)),
		tidx(model->createIndex(order, 1, this))
	{
		printf("Created config file %s\n", name.toLocal8Bit().data());
		const QDomNodeList &sectionElements(configElement.elementsByTagNameNS(CONFIG_URI, "section"));
		for (int i = 0; i < sectionElements.count(); i ++)
			sections << new Section(sectionElements.at(i).toElement(), model, i, this);
	}
	const QString name;
	QList<Section *> sections;
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
		if (cf) {
			Section *s = cf->sections[row];
			return column ? s->typeIdx : s->nameIdx;
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
	assert(0);
}

int ConfigModel::rowCount(const QModelIndex &parent) const {
	if (parent.isValid()) {
		const Elem *data = static_cast<const Elem *>(parent.internalPointer());
		const ConfigFile *cf = dynamic_cast<const ConfigFile *>(data);
		if (cf)
			return cf->sections.size();
		else
			return 0;
	} else
		return configs.size();
}

int ConfigModel::columnCount(const QModelIndex &parent) const {
	if (parent.isValid()) {
		const Elem *data = static_cast<const Elem *>(parent.internalPointer());
		const ConfigFile *cf = dynamic_cast<const ConfigFile *>(data);
		if (cf)
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
	switch (role) {
		case Qt::DisplayRole:
			if (cf)
				return index.column() ? "config" : cf->name;
			if (s)
				return index.column() ? s->type : s->name;
		default:
			printf("Other\n");
			return QVariant();
	}
}

QVariant ConfigModel::headerData(int section, Qt::Orientation orientation, int role) const {
	if (orientation != Qt::Horizontal || role != Qt::DisplayRole)
		return QVariant();
	return section ? "type/value" : "name";
}
